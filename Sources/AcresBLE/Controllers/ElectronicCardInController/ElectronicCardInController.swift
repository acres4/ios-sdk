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
    private var onInsertPlayerCard: ((Result<Void, AcresBLEError>) -> Void)?
    private var insertionState: Bool = false
    private var onRemovePlayerCard: ((Result<Void, AcresBLEError>) -> Void)?
    
    // Timeout Task
    internal lazy var timeOutTask = DispatchWorkItem { [weak self] in
        if self?.service.isScanning() ?? false {
            self?.service.stopScanning()
            self?.onInsertPlayerCard?(.failure(.scanTimeout))
        }
    }
    
    // MARK: - ElectronicCardInControllerProtocol

    public func insertPlayerCard(id: String, completion: @escaping (Result<Void, AcresBLEError>) -> Void) {
        self.currentCardId = id
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
            if self.insertionState {
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
                    guard let currentCardId = self.currentCardId else { return }
                    self.writeToPlayerCardTrack1(id: currentCardId)
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
                    self.service.cancelCurrentPeripheralConnection()
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
            
            if rssi >= self.rssiLimit {
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
    
    private func writeToPlayerCardTrack1(id: String) {
        if let data = id.data(using: .utf8) {
            service.writeDataOperation(data, for: .playerCardTrack1Characteristic)
        }
    }
    
    private func writeToPlayerCardInsert(_ bool: Bool) {
        let byteArray = byteArray(from: bool.toUInt8)
        let data = Data(byteArray)
        service.writeDataOperation(data, for: .playerCardInsertCharacteristic)
    }
    
    private func disconnect() {
        service.cancelCurrentPeripheralConnection()
    }
    
    private func resetState() {
        currentCardId = nil
        onInsertPlayerCard = nil
        insertionState = false
        onRemovePlayerCard = nil
    }
}
