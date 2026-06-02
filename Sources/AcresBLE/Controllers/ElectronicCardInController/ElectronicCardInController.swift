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
        internal var rssiLimit: Int {
    //        return -100 // experiment based value
            return -55 // experiment based value
        }
        
        internal var countLimit: Int{
            return 15
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
            self?.stopScan()
            self?.timeOutTask.cancel()
            self?.scheduleOperations()
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

            if uuid == .playerCardBusyCharacteristic {
                if let error = error {
                    Logger.error(error.localizedDescription)
                    self.onInsertPlayerCard?(.failure(.generic(error)))
                    return
                }

                if (value?[0].toBool ?? true) {
                    self.onInsertPlayerCard?(.failure(.playerCardBusy))
                } else {
                    guard
                        let cardTrack = self.cardTrack,
                        let currentCardId = self.currentCardId,
                        let currentCardIdData = currentCardId.data(using: .utf8)
                    else { return }

                    Logger.debug("Card id size in bytes: \(currentCardIdData.count))")
                    guard currentCardIdData.count < cardTrack.maxBytesSizeToWrite else {

                        Logger.debug("Failed to write in card track \(cardTrack.rawValue), max size bytes is \(cardTrack.maxBytesSizeToWrite)")
                        self.onInsertPlayerCard?(.failure(cardTrack.maxBytesSizeToWriteError ))
                        return
                    }

                    Logger.debug("Write in player card track: \(cardTrack.rawValue))")
                    self.service.writeDataOperation(currentCardIdData, for: cardTrack.characteristicNumber)

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
        service.readDataOperation(for: .playerCardBusyCharacteristic)
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
    }
}
