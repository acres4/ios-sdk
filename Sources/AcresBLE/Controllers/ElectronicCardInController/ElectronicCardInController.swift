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
    private var pendingInsertOutcome: Result<Void, AcresBLEError>?

    // Remove-flow state
    private var onRemovePlayerCard: ((Result<Void, AcresBLEError>) -> Void)?
    private var pendingRemoveOutcome: Result<Void, AcresBLEError>?

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
        if let p = service.getPeripheral(), p.state == .connected {
            // Reuse the existing connection (e.g. one left open by SlotAndTableController.findDevice).
            // A fresh scan+connect would be a no-op because BLEService.connect early-returns when
            // the peripheral is already connected, and no new didDiscoverCharacteristicsFor would fire.
            service.readDataOperation(for: .playerCardBusyCharacteristic)
        } else {
            beginScan()
        }
    }

    public func removePlayerCard(completion: @escaping (Result<Void, AcresBLEError>) -> Void) {
        onRemovePlayerCard = completion
        setupRemoveFlow()
        if let p = service.getPeripheral(), p.state == .connected {
            // Same reuse-existing-connection guard as insertPlayerCard.
            writeToPlayerCardInsert(false)
        } else {
            beginScan()
        }
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
            self.handleDisconnectForInsertFlow(error: error)
        }

        service.didFailToConnect = { [weak self] _, error in
            guard let self = self else { return }
            self.handleFailToConnectForInsertFlow(error: error)
        }

        service.didUpdateValueFor = { [weak self] _, value, uuid, error in
            guard let self = self, uuid == .playerCardBusyCharacteristic else { return }

            if let error = error {
                Logger.error(error.localizedDescription)
                self.terminateInsertFlow(with: .failure(.generic(error)))
                return
            }

            if (value?[0].toBool ?? true) {
                self.terminateInsertFlow(with: .failure(.playerCardBusy))
                return
            }

            guard
                let cardTrack = self.cardTrack,
                let currentCardId = self.currentCardId,
                let cardIdData = currentCardId.data(using: .utf8)
            else {
                self.terminateInsertFlow(with: .failure(.unknown))
                return
            }

            Logger.debug("Card id size in bytes: \(cardIdData.count)")
            guard cardIdData.count < cardTrack.maxBytesSizeToWrite else {
                Logger.debug("Card ID too long for track \(cardTrack.rawValue); max \(cardTrack.maxBytesSizeToWrite) bytes")
                self.terminateInsertFlow(with: .failure(cardTrack.maxBytesSizeToWriteError))
                return
            }

            self.service.writeDataOperation(cardIdData, for: cardTrack.characteristicNumber)
        }

        service.didWriteValueFor = { [weak self] uuid, error in
            guard let self = self else { return }

            if uuid == .playerCardTrack1Characteristic {
                if error != nil {
                    self.terminateInsertFlow(with: .failure(.playerCardTrack1FailedToRecord))
                    return
                }
                self.writeToPlayerCardInsert(true)
                return
            }

            if uuid == .playerCardTrack2Characteristic {
                if error != nil {
                    self.terminateInsertFlow(with: .failure(.playerCardTrack2FailedToRecord))
                    return
                }
                self.writeToPlayerCardInsert(true)
                return
            }

            if uuid == .playerCardInsertCharacteristic {
                if error != nil {
                    self.terminateInsertFlow(with: .failure(.playerCardInsertFail))
                    return
                }
                // Success: disconnect first, fire success callback only after didDisconnect.
                // This serializes ops so the next call (e.g. removePlayerCard) doesn't
                // race the in-flight disconnect.
                self.terminateInsertFlow(with: .success(()))
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
            self.handleDisconnectForRemoveFlow(error: error)
        }

        service.didFailToConnect = { [weak self] _, error in
            guard let self = self else { return }
            self.handleFailToConnectForRemoveFlow(error: error)
        }

        service.didUpdateValueFor = { _, _, _, _ in }

        service.didWriteValueFor = { [weak self] uuid, error in
            guard let self = self, uuid == .playerCardInsertCharacteristic else { return }

            if let error = error {
                self.terminateRemoveFlow(with: .failure(.generic(error)))
                return
            }
            self.terminateRemoveFlow(with: .success(()))
        }
    }

    // MARK: - Disconnect / fail-to-connect handlers
    //
    // Three cases per flow:
    //   1. pendingOutcome != nil — terminate*Flow set an outcome and triggered the
    //      disconnect. Fire it now and reset.
    //   2. pendingOutcome == nil, disconnectInitiated == false — the peripheral
    //      dropped on its own (out of range, EGM rebooted). Fire .didDisconnect
    //      failure and reset.
    //   3. pendingOutcome == nil, disconnectInitiated == true — stale disconnect
    //      from a *prior* op whose handlers were replaced before its disconnect
    //      completed. Don't fire anything, don't reset our new state — just clear
    //      the flag so our own future disconnect path works.

    private func handleDisconnectForInsertFlow(error: Error?) {
        if let outcome = pendingInsertOutcome {
            pendingInsertOutcome = nil
            fireInsertCompletion(outcome)
            resetState()
            return
        }
        if !disconnectInitiated {
            fireInsertCompletion(.failure(.didDisconnect(error)))
            resetState()
            return
        }
        disconnectInitiated = false
    }

    private func handleFailToConnectForInsertFlow(error: Error?) {
        if let outcome = pendingInsertOutcome {
            pendingInsertOutcome = nil
            fireInsertCompletion(outcome)
            resetState()
            return
        }
        if onInsertPlayerCard != nil {
            fireInsertCompletion(.failure(.didFailToConnect(error)))
            resetState()
        }
    }

    private func handleDisconnectForRemoveFlow(error: Error?) {
        if let outcome = pendingRemoveOutcome {
            pendingRemoveOutcome = nil
            fireRemoveCompletion(outcome)
            resetState()
            return
        }
        if !disconnectInitiated {
            fireRemoveCompletion(.failure(.didDisconnect(error)))
            resetState()
            return
        }
        disconnectInitiated = false
    }

    private func handleFailToConnectForRemoveFlow(error: Error?) {
        if let outcome = pendingRemoveOutcome {
            pendingRemoveOutcome = nil
            fireRemoveCompletion(outcome)
            resetState()
            return
        }
        if onRemovePlayerCard != nil {
            fireRemoveCompletion(.failure(.didFailToConnect(error)))
            resetState()
        }
    }

    // MARK: - Terminate helpers
    //
    // The contract: the user's completion handler always fires after the BLE
    // connection has been fully torn down. If a peripheral is connected (or
    // mid-connection), defer the outcome to didDisconnect/didFailToConnect. If no
    // peripheral exists yet (e.g. scan timeout before any device was discovered),
    // fire immediately.

    private func terminateInsertFlow(with outcome: Result<Void, AcresBLEError>) {
        if let p = service.getPeripheral(), p.state != .disconnected {
            pendingInsertOutcome = outcome
            initiateDisconnect()
        } else {
            fireInsertCompletion(outcome)
            resetState()
        }
    }

    private func terminateRemoveFlow(with outcome: Result<Void, AcresBLEError>) {
        if let p = service.getPeripheral(), p.state != .disconnected {
            pendingRemoveOutcome = outcome
            initiateDisconnect()
        } else {
            fireRemoveCompletion(outcome)
            resetState()
        }
    }

    // MARK: - Scan / connect

    private func beginScan() {
        service.discovered = { [weak self] peripheral, _, rssi in
            guard let self = self else { return }
            if rssi >= self.rssiLimit {
                self.connect(to: peripheral)
            }
        }

        service.startScanning(allowDuplicates: true)

        timeOutTask = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.service.isScanning() {
                self.service.stopScanning()
            }
            if self.onInsertPlayerCard != nil {
                self.terminateInsertFlow(with: .failure(.scanTimeout))
            } else if self.onRemovePlayerCard != nil {
                self.terminateRemoveFlow(with: .failure(.scanTimeout))
            }
        }
        scheduleTimeout(task: timeOutTask)
    }

    // MARK: - Helpers

    // Fire-and-clear: nil the callback the moment we invoke it so any later
    // unexpected event becomes a no-op.
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
        pendingInsertOutcome = nil
        pendingRemoveOutcome = nil
        disconnectInitiated = false
    }
}