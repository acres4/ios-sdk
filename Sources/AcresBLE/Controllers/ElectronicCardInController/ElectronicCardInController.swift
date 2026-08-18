//
//  ElectronicCardInController.swift
//
//
//  Created by Jozo Mostarac on 22.07.2022..
//

import Foundation

public class ElectronicCardInController: ElectronicCardInControllerProtocol, CommonControllerProtocol {
    var service: BLEServiceProtocol

    init(service: BLEServiceProtocol = BLEService()) {
        self.service = service
    }

    // Internal state
    private var currentCardId: String?
    private var cardTrack: CardTrack?
    private var onInsertPlayerCard: ((Result<Void, AcresBLEError>) -> Void)?
    private var insertionState: Bool = false
    private var onRemovePlayerCard: ((Result<Void, AcresBLEError>) -> Void)?
    private var disconnectInitiated: Bool = false
    private var deviceMap: [UUID: Int] = [:]
    /// True while the pending insert-characteristic write is clearing someone
    /// else's session rather than carding us in.
    private var pendingForcedRemoval: Bool = false
        internal var rssiLimit: Int {
    //        return -100 // experiment based value
            return -55 // experiment based value
        }
        
        internal var countLimit: Int{
            return 6
        }

        /// Settle time between GATT operations during card-in. Currently unused —
        /// the per-step delays are bypassed, matching Android, since they never
        /// affected the card-in failures. Kept so they are easy to reinstate.
        internal var operationDelay: TimeInterval {
            return 0.5
        }

        /// Pause after clearing another session's card before writing ours. The
        /// EGM needs a moment to register the removal.
        internal var cardRemovalSettle: TimeInterval {
            return 2.0
        }

    /// Runs `block` after `operationDelay`. Callbacks arrive on the central
    /// manager's queue; hopping to main keeps the sequencing predictable.
    private func afterOperationDelay(_ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + operationDelay, execute: block)
    }

    // Timeout Task
    internal lazy var timeOutTask = DispatchWorkItem { [weak self] in
        if self?.service.isScanning() ?? false {
            self?.service.stopScanning()
            self?.onInsertPlayerCard?(.failure(.scanTimeout))
        }
    }

    // MARK: - ElectronicCardInControllerProtocol

    public func insertPlayerCard(id: String, cardTrack: CardTrack, completion: @escaping (Result<Void, AcresBLEError>) -> Void) {
        self.currentCardId = id
        self.cardTrack = cardTrack
        self.onInsertPlayerCard = completion
        self.insertionState = true
        startScan()
        scheduleTimeout(task: timeOutTask)
    }

    public func removePlayerCard(completion: @escaping (Result<Void, AcresBLEError>) -> Void) {
        guard
            let connectedPeripheral = service.getPeripheral(),
            connectedPeripheral.state == .connected
        else {
            completion(.failure(.notConnected))
            return
        }
        self.insertionState = false
        self.onRemovePlayerCard = completion
        // Re-install our closures on the shared BLEService. A prior SlotAndTable op
        // (e.g. findDevice) may have replaced them, in which case our didWriteValueFor
        // branch for .playerCardInsertCharacteristic — which fires onRemovePlayerCard
        // and initiateDisconnect — would never run.
        setupConnection()
        writeToPlayerCardInsert(false)
    }

    // MARK: - CommonControllerProtocol

    internal func setupConnection() {
        service.didDiscoverCharacteristicsFor = { [weak self] peripheral in
            Logger.debug("didDiscoverCharacteristicsFor: \(peripheral.identifier))")
            guard let self = self else { return }
            self.stopScan()
            self.timeOutTask.cancel()
            self.scheduleOperations()
        }

        service.didDisconnect = { [weak self] peripheral, error in
            guard let self = self else { return }
            if !self.disconnectInitiated {
                self.onInsertPlayerCard?(.failure(.didDisconnect(error)))
            }
            self.resetState()
        }

        service.didFailToConnect = { [weak self] peripheral, error in
            if error != nil {
                self?.onInsertPlayerCard?(.failure(.didFailToConnect()))
            }
            self?.resetState()
        }

        service.didUpdateValueFor = { [weak self] peripheral, value, uuid, error in
            guard let self = self else { return }

            // Occupancy check reads the INSERT characteristic, not the mechanical
            // playerCardBusy flag: what blocks a card-in is another electronic
            // session already held on the EGM. A missing byte counts as occupied.
            if uuid == .playerCardInsertCharacteristic {
                if let error = error {
                    Logger.error(error.localizedDescription)
                    self.onInsertPlayerCard?(.failure(.generic(error)))
                    return
                }

                let occupied = value?.first.map { $0 == 0x01 } ?? true
                Logger.debug("insertPlayerCard: occupied=\(occupied)")

                if occupied, let cardTrack = self.cardTrack {
                    // Might be our own stale session. Read back the stored track
                    // and compare before forcing anything.
                    Logger.debug("insertPlayerCard: reading track to identify holder")
                    self.service.readDataOperation(for: cardTrack.characteristicNumber)
                } else {
                    self.writePlayerCardTrack()
                }
            }

            // Read response from the occupancy check above.
            if uuid == .playerCardTrack1Characteristic || uuid == .playerCardTrack2Characteristic {
                if let error = error {
                    Logger.error(error.localizedDescription)
                    self.onInsertPlayerCard?(.failure(.generic(error)))
                    return
                }

                let expected = self.currentCardId?.data(using: .utf8) ?? Data()
                Logger.debug("current track:  \(value?.hexString ?? "<unreadable>")")
                Logger.debug("expected track: \(expected.hexString)")
                let ours = self.tracksMatch(value, expected)
                Logger.debug("insertPlayerCard: existing session is ours=\(ours)")

                if ours {
                    // Already carded in under this id — just rewrite it.
                    self.writePlayerCardTrack()
                } else {
                    // Someone else's session. Clear it, let the EGM settle, then
                    // card in anyway rather than failing.
                    Logger.debug("insertPlayerCard: forcing removal of existing session")
                    self.pendingForcedRemoval = true
                    self.writeToPlayerCardInsert(false)
                }
            }
        }

        service.didWriteValueFor = { [weak self] uuid, error in
            guard let self = self else { return }

            if uuid == .playerCardTrack1Characteristic {
                if error != nil {
                    self.onInsertPlayerCard?(.failure(.playerCardTrack1FailedToRecord))
                    return
                }

                self.writeToPlayerCardInsert(error == nil)
            }

            if uuid == .playerCardTrack2Characteristic {
                if error != nil {
                    self.onInsertPlayerCard?(.failure(.playerCardTrack2FailedToRecord))
                    return
                }

                self.writeToPlayerCardInsert(error == nil)
            }

            if uuid == .playerCardInsertCharacteristic {
                if let error = error {
                    self.onInsertPlayerCard?(.failure(.playerCardInsertFail))
                    self.onRemovePlayerCard?(.failure(.generic(error)))
                    return
                }

                // A forced removal writes 0 to this same characteristic mid card-in.
                // Without this branch it would land in `case true` below and report
                // the card-in as complete before anything had been written.
                if self.pendingForcedRemoval {
                    self.pendingForcedRemoval = false
                    Logger.debug("insertPlayerCard: existing session cleared, settling")
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.cardRemovalSettle) {
                        [weak self] in
                        self?.writePlayerCardTrack()
                    }
                    return
                }

                switch self.insertionState {
                case true:
                    self.onInsertPlayerCard?(.success(()))
                case false:
                    self.onRemovePlayerCard?(.success(()))
                    self.initiateDisconnect()
                }
            }
        }
    }

    internal func startScan() {
        setupConnection()
        
        if let device = service.getPeripheral(), device.state == .connected {
            scheduleOperations()
            return
        }
        
        service.startScanning(allowDuplicates: true)
        
        service.discovered = { [weak self] peripheral, bleAdvertisingData, rssi in
            guard let self = self else { return }
            
            var currentCount = 0
            
            // Check for key in the current map, if it doesn't exist add it
            let keyExists = self.deviceMap[peripheral.identifier] != nil
            if !keyExists {
                self.deviceMap[peripheral.identifier] = 0
            }
            // Create temp variable to adjust values to the map
            currentCount = self.deviceMap[peripheral.identifier] ?? 0
            if rssi >= self.rssiLimit {
                currentCount = currentCount + 1
                self.deviceMap[peripheral.identifier] = currentCount
            } else if rssi > -99 {
                // if we get an good read that was less than our minimum reset the count in the map
                currentCount = 0
                self.deviceMap[peripheral.identifier] = currentCount
            }
            if self.deviceMap[peripheral.identifier] ?? 0 > self.countLimit {
                print(self.deviceMap)
                self.deviceMap = [:]
                self.connect(to: peripheral)
            }
        
        }
    }

    internal func connect(to device: CBPeripheralProtocol) {
        service.connect(to: device)
    }

    internal func stopScan() {
        service.stopScanning()
    }

    // MARK: - Helpers

    private func scheduleOperations() {
        service.readDataOperation(for: .playerCardInsertCharacteristic)
    }

    /// Validates the id and writes it to the selected track. Split out because
    /// three paths reach it: an unoccupied EGM, our own stale session, and a
    /// forced removal of someone else's.
    /// True when the track already on the EGM is this player's.
    ///
    /// The stored value rarely comes back byte-identical to what was written: EGMs
    /// pad the buffer to the characteristic's fixed width, and some return only the
    /// portion they kept. So compare with padding trimmed, and accept either value
    /// being a prefix of the other.
    private func tracksMatch(_ stored: Data?, _ expected: Data) -> Bool {
        guard let stored = stored else { return false }
        let a = stored.trimmedTrackPadding()
        let b = expected.trimmedTrackPadding()
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        if a.count > b.count { return a.prefix(b.count) == b }
        return b.prefix(a.count) == a
    }

    private func writePlayerCardTrack() {
        guard
            let cardTrack = self.cardTrack,
            let currentCardId = self.currentCardId,
            let currentCardIdData = currentCardId.data(using: .utf8)
        else { return }

        Logger.debug("Card id size in bytes: \(currentCardIdData.count))")
        guard currentCardIdData.count < cardTrack.maxBytesSizeToWrite else {
            Logger.debug("Failed to write in card track \(cardTrack.rawValue), max size bytes is \(cardTrack.maxBytesSizeToWrite)")
            onInsertPlayerCard?(.failure(cardTrack.maxBytesSizeToWriteError))
            return
        }

        Logger.debug("Write in player card track: \(cardTrack.rawValue))")
        service.writeDataOperation(currentCardIdData, for: cardTrack.characteristicNumber)
    }

    private func writeToPlayerCardInsert(_ bool: Bool) {
        let byteArray = byteArray(from: bool.toUInt8)
        let data = Data(byteArray)
        service.writeDataOperation(data, for: .playerCardInsertCharacteristic)
    }

    private func disconnect() {
        service.cancelCurrentPeripheralConnection()
    }

    private func initiateDisconnect() {
        disconnectInitiated = true
        service.cancelCurrentPeripheralConnection()
    }

    private func resetState() {
        currentCardId = nil
        onInsertPlayerCard = nil
        insertionState = false
        onRemovePlayerCard = nil
        disconnectInitiated = false
        pendingForcedRemoval = false
    }
}

private extension Data {
    /// Strips the padding EGMs use to fill a fixed-width track buffer.
    func trimmedTrackPadding() -> Data {
        let padding: Set<UInt8> = [0x00, 0x20, 0xFF]
        var slice = self[...]
        while let first = slice.first, padding.contains(first) { slice = slice.dropFirst() }
        while let last = slice.last, padding.contains(last) { slice = slice.dropLast() }
        return Data(slice)
    }
}
