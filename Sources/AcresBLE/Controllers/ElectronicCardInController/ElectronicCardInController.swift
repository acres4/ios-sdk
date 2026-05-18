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

    // Insert-flow state
    private var currentCardId: String?
    private var cardTrack: CardTrack?
    private var onInsertPlayerCard: ((Result<Void, AcresBLEError>) -> Void)?

    // Remove-flow state
    private var onRemovePlayerCard: ((Result<Void, AcresBLEError>) -> Void)?

    // Shared
    private var disconnectInitiated: Bool = false

    // Per-call timeout. DispatchWorkItem can only be scheduled once, so we replace
    // it on every public call instead of using a `lazy var`.
    internal var timeOutTask: DispatchWorkItem = DispatchWorkItem(block: {})

    // MARK: - ElectronicCardInControllerProtocol

    public func insertPlayerCard(id: String, cardTrack: CardTrack, completion: @escaping (Result<Void, AcresBLEError>) -> Void) {
        currentCardId = id
        self.cardTrack = cardTrack
        onInsertPlayerCard = completion
        setupInsertFlow()
        beginScan()
    }

    public func removePlayerCard(completion: @escaping (Result<Void, AcresBLEError>) -> Void) {
        onRemovePlayerCard = completion
        setupRemoveFlow()
        beginScan()
    }

    // MARK: - CommonControllerProtocol (Option B: per-flow setup replaces shared setupConnection)

    internal func setupConnection() {}
    internal func startScan() {}
    internal func connect(to device: CBPeripheralProtocol) { service.connect(to: device) }
    internal func stopScan() { service.stopScanning() }

    // MARK: - Flow installers

    private func setupInsertFlow() {
        service.didDiscoverCharacteristicsFor = { [weak self] peripheral in
            guard let self = self else { return }
            Logger.debug("insert: didDiscoverCharacteristicsFor \(peripheral.identifier)")
            self.stopScan()
            self.timeOutTask.cancel()
            self.service.readDataOperation(for: .playerCardBusyCharacteristic)
        }

        service.didDisconnect = { [weak self] _, error in
            guard let self = self else { return }
            if !self.disconnectInitiated {
                self.fireInsertCompletion(.failure(.didDisconnect(error)))
            }
            self.resetState()
        }

        service.didFailToConnect = { [weak self] _, error in
            guard let self = self else { return }
            self.fireInsertCompletion(.failure(.didFailToConnect(error)))
            self.resetState()
        }

        service.didUpdateValueFor = { [weak self] _, value, uuid, error in
            guard let self = self, uuid == .playerCardBusyCharacteristic else { return }

            if let error = error {
                Logger.error(error.localizedDescription)
                self.fireInsertCompletion(.failure(.generic(error)))
                self.initiateDisconnect()
                return
            }

            if (value?[0].toBool ?? true) {
                self.fireInsertCompletion(.failure(.playerCardBusy))
                self.initiateDisconnect()
                return
            }

            guard
                let cardTrack = self.cardTrack,
                let currentCardId = self.currentCardId,
                let cardIdData = currentCardId.data(using: .utf8)
            else { return }

            Logger.debug("Card id size in bytes: \(cardIdData.count)")
            guard cardIdData.count < cardTrack.maxBytesSizeToWrite else {
                Logger.debug("Card ID too long for track \(cardTrack.rawValue); max \(cardTrack.maxBytesSizeToWrite) bytes")
                self.fireInsertCompletion(.failure(cardTrack.maxBytesSizeToWriteError))
                self.initiateDisconnect()
                return
            }

            self.service.writeDataOperation(cardIdData, for: cardTrack.characteristicNumber)
        }

        service.didWriteValueFor = { [weak self] uuid, error in
            guard let self = self else { return }

            if uuid == .playerCardTrack1Characteristic {
                if error != nil {
                    self.fireInsertCompletion(.failure(.playerCardTrack1FailedToRecord))
                    self.initiateDisconnect()
                    return
                }
                self.writeToPlayerCardInsert(true)
                return
            }

            if uuid == .playerCardTrack2Characteristic {
                if error != nil {
                    self.fireInsertCompletion(.failure(.playerCardTrack2FailedToRecord))
                    self.initiateDisconnect()
                    return
                }
                self.writeToPlayerCardInsert(true)
                return
            }

            if uuid == .playerCardInsertCharacteristic {
                if error != nil {
                    self.fireInsertCompletion(.failure(.playerCardInsertFail))
                    self.initiateDisconnect()
                    return
                }
                // Disconnect after every successful insert so the EGM is released
                // even if the player walks away with the card still inserted.
                self.fireInsertCompletion(.success(()))
                self.initiateDisconnect()
            }
        }
    }

    private func setupRemoveFlow() {
        service.didDiscoverCharacteristicsFor = { [weak self] peripheral in
            guard let self = self else { return }
            Logger.debug("remove: didDiscoverCharacteristicsFor \(peripheral.identifier)")
            self.stopScan()
            self.timeOutTask.cancel()
            self.writeToPlayerCardInsert(false)
        }

        service.didDisconnect = { [weak self] _, error in
            guard let self = self else { return }
            if !self.disconnectInitiated {
                self.fireRemoveCompletion(.failure(.didDisconnect(error)))
            }
            self.resetState()
        }

        service.didFailToConnect = { [weak self] _, error in
            guard let self = self else { return }
            self.fireRemoveCompletion(.failure(.didFailToConnect(error)))
            self.resetState()
        }

        service.didUpdateValueFor = { _, _, _, _ in }

        service.didWriteValueFor = { [weak self] uuid, error in
            guard let self = self, uuid == .playerCardInsertCharacteristic else { return }

            if let error = error {
                self.fireRemoveCompletion(.failure(.generic(error)))
                self.initiateDisconnect()
                return
            }
            self.fireRemoveCompletion(.success(()))
            self.initiateDisconnect()
        }
    }

    // MARK: - Scan / connect

    private func beginScan() {
        // Always scan fresh — disconnect-after-success means we never carry over a connection.
        service.startScanning(allowDuplicates: true)

        service.discovered = { [weak self] peripheral, _, rssi in
            guard let self = self else { return }
            if rssi >= self.rssiLimit {
                self.connect(to: peripheral)
            }
        }

        timeOutTask = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.service.isScanning() {
                self.service.stopScanning()
            }
            // Abort any in-flight connection so post-timeout discovery callbacks don't fire writes.
            self.disconnectInitiated = true
            self.service.cancelCurrentPeripheralConnection()

            if self.onInsertPlayerCard != nil {
                self.fireInsertCompletion(.failure(.scanTimeout))
            } else if self.onRemovePlayerCard != nil {
                self.fireRemoveCompletion(.failure(.scanTimeout))
            }
            self.resetState()
        }
        scheduleTimeout(task: timeOutTask)
    }

    // MARK: - Helpers

    // Fire-and-clear: nil the callback the moment we invoke it so any later disconnect/timeout
    // path is naturally a no-op. Removes whole class of double-callback bugs.
    private func fireInsertCompletion(_ result: Result<Void, AcresBLEError>) {
        let cb = onInsertPlayerCard
        onInsertPlayerCard = nil
        cb?(result)
    }

    private func fireRemoveCompletion(_ result: Result<Void, AcresBLEError>) {
        let cb = onRemovePlayerCard
        onRemovePlayerCard = nil
        cb?(result)
    }

    private func writeToPlayerCardInsert(_ bool: Bool) {
        let bytes = byteArray(from: bool.toUInt8)
        let data = Data(bytes)
        service.writeDataOperation(data, for: .playerCardInsertCharacteristic)
    }

    private func initiateDisconnect() {
        disconnectInitiated = true
        service.cancelCurrentPeripheralConnection()
    }

    private func resetState() {
        currentCardId = nil
        cardTrack = nil
        onInsertPlayerCard = nil
        onRemovePlayerCard = nil
        disconnectInitiated = false
    }
}