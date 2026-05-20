//
//  ElectronicCardInController.swift
//
//
//  Created by Jozo Mostarac on 22.07.2022..
//

import CoreBluetooth
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

    // Per-call timeout. DispatchWorkItem can only be scheduled once, so we replace
    // it on every public call instead of using a `lazy var`.
    internal var timeOutTask: DispatchWorkItem = DispatchWorkItem(block: {})

    // MARK: - ElectronicCardInControllerProtocol

    public func insertPlayerCard(id: String, cardTrack: CardTrack, completion: @escaping (Result<Void, AcresBLEError>) -> Void) {
        Logger.debug("insertPlayerCard called; peripheral state: \(describe(service.getPeripheral()?.state))")
        currentCardId = id
        self.cardTrack = cardTrack
        onInsertPlayerCard = completion
        setupInsertFlow()
        if let p = service.getPeripheral(), p.state == .connected {
            Logger.debug("insertPlayerCard: reusing existing connection — read playerCardBusy")
            service.readDataOperation(for: .playerCardBusyCharacteristic)
        } else {
            Logger.debug("insertPlayerCard: no existing connection — beginScan")
            beginScan()
        }
    }

    public func removePlayerCard(completion: @escaping (Result<Void, AcresBLEError>) -> Void) {
        Logger.debug("removePlayerCard called; peripheral state: \(describe(service.getPeripheral()?.state))")
        onRemovePlayerCard = completion
        setupRemoveFlow()
        if let p = service.getPeripheral(), p.state == .connected {
            Logger.debug("removePlayerCard: reusing existing connection — write 0 to playerCardInsert")
            writeToPlayerCardInsert(false)
        } else {
            Logger.debug("removePlayerCard: no existing connection — beginScan")
            beginScan()
        }
    }

    private func describe(_ state: CBPeripheralState?) -> String {
        guard let state = state else { return "nil (no peripheral)" }
        switch state {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }

    // CommonControllerProtocol (Option B: per-flow setup replaces shared setupConnection)

    internal func setupConnection() {}
    internal func startScan() {}
    internal func connect(to device: CBPeripheralProtocol) { service.connect(to: device) }
    internal func stopScan() { service.stopScanning() }

    // Flow installers

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

            if (value?.first?.toBool ?? true) {
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

    // Disconnect / fail-to-connect handlers
    //
    // The controller no longer initiates disconnects internally — the consumer
    // owns the connection lifecycle via slotAndTableController.disconnectFromDevice.
    // So any disconnect/fail-to-connect that fires here is either:
    //   - An in-flight op being interrupted by the EGM/radio dropping (or by the
    //     consumer disconnecting mid-op): fire failure on the active completion.
    //   - A disconnect after the op already completed (consumer-initiated cleanup):
    //     completion is already nil, so fire is a no-op.

    private func handleDisconnectForInsertFlow(error: Error?) {
        if onInsertPlayerCard != nil {
            fireInsertCompletion(.failure(.didDisconnect(error)))
        }
        resetState()
    }

    private func handleFailToConnectForInsertFlow(error: Error?) {
        if onInsertPlayerCard != nil {
            fireInsertCompletion(.failure(.didFailToConnect(error)))
        }
        resetState()
    }

    private func handleDisconnectForRemoveFlow(error: Error?) {
        if onRemovePlayerCard != nil {
            fireRemoveCompletion(.failure(.didDisconnect(error)))
        }
        resetState()
    }

    private func handleFailToConnectForRemoveFlow(error: Error?) {
        if onRemovePlayerCard != nil {
            fireRemoveCompletion(.failure(.didFailToConnect(error)))
        }
        resetState()
    }

    // Terminate helpers — fire the completion immediately and reset per-flow state.
    // The connection stays open; consumer disconnects via slotAndTableController.

    private func terminateInsertFlow(with outcome: Result<Void, AcresBLEError>) {
        fireInsertCompletion(outcome)
        resetState()
    }

    private func terminateRemoveFlow(with outcome: Result<Void, AcresBLEError>) {
        fireRemoveCompletion(outcome)
        resetState()
    }

    // Scan / connect

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

    private func resetState() {
        currentCardId = nil
        cardTrack = nil
        onInsertPlayerCard = nil
        onRemovePlayerCard = nil
    }
}