//
//  SlotAndTableController.swift
//
//
//  Created by Jozo Mostarac on 22.07.2022..
//
import Foundation

public class SlotAndTableController: SlotAndTableControllerProtocol, CommonControllerProtocol {
    var service: BLEServiceProtocol
    
    init(service: BLEServiceProtocol = BLEService()) {
        self.service = service
    }
        
    internal var rssiLimit: Int {
//        return -100 // experiment based value
        return -55 // experiment based value
    }
    
    internal var countLimit: Int{
        return 15
    }
    
    // Internal state
    private var onFindDevice: ((Result<String, AcresBLEError>) -> Void)?
    private var onFundTable: ((Result<String, AcresBLEError>) -> Void)?
    private var onCashOutTable: ((Result<Int, AcresBLEError>) -> Void)?
    private var onCancelCashOut: ((Result<Void, AcresBLEError>) -> Void)?
    private var onDisconnectFromDevice: ((Result<Void, AcresBLEError>) -> Void)?
    private var disconnectInitiated: Bool = false
    private var amountRequested: Int?
    private var operationScheduled: Bool = false
    private var connectedToTable: Bool = false
    private var currentCount: Int = 0
    private var deviceMap: [UUID: Int] = [:]
    
    // Timeout Task
    internal lazy var timeOutTask = DispatchWorkItem { [weak self] in
        if self?.service.isScanning() ?? false {
            self?.service.stopScanning()
            self?.onFindDevice?(.failure(.scanTimeout))
        }
    }
    
    // MARK: - SlotAndTableControllerProtocol
    
    public func findDevice(completion: @escaping (Result<String, AcresBLEError>) -> Void) {
        onFindDevice = completion
        startScan()
        scheduleTimeout(task: timeOutTask)
    }
    
    public func fundTable(amount: Int, completion: @escaping (Result<String, AcresBLEError>) -> Void) {
        guard
            let connectedPeripheral = service.getPeripheral(),
            connectedPeripheral.state == .connected
        else {
            completion(.failure(.notConnected))
            return
        }
        guard connectedToTable else {
            completion(.failure(.notConnectedToTable))
            return
        }
        onFundTable = completion
        amountRequested = amount
        writeAmountToTable(amount: amount)
    }
    
    public func cashOutTable(completion: @escaping (Result<Int, AcresBLEError>) -> Void) {
        guard
            let connectedPeripheral = service.getPeripheral(),
            connectedPeripheral.state == .connected
        else {
            completion(.failure(.notConnected))
            return
        }
        guard connectedToTable else {
            completion(.failure(.notConnectedToTable))
            return
        }
        onCashOutTable = completion
        amountRequested = 0
        writeAmountToTable(amount: 0)
    }
    
    public func cancelCashOut(completion: @escaping (Result<Void, AcresBLEError>) -> Void) {
        guard
            let connectedPeripheral = service.getPeripheral(),
            connectedPeripheral.state == .connected
        else {
            completion(.failure(.notConnected))
            return
        }
        guard connectedToTable else {
            completion(.failure(.notConnectedToTable))
            return
        }
        onCancelCashOut = completion
        writeToCancelCashOut()
    }
    
    public func disconnectFromDevice(completion: @escaping (Result<Void, AcresBLEError>) -> Void) {
        guard
            let connectedPeripheral = service.getPeripheral(),
            connectedPeripheral.state == .connected
        else {
            completion(.failure(.notConnected))
            return
        }
        onDisconnectFromDevice = completion
        initiateDisconnect()
    }
    
    // MARK: - CommonControllerProtocol
    
    internal func setupConnection() {
        service.didDiscoverCharacteristicsFor = { [weak self] peripheral in
            guard let self = self else { return }
            Logger.debug("didDiscoverCharacteristicsFor: \(peripheral.identifier))")
            self.stopScan()
            self.timeOutTask.cancel()
            if !self.operationScheduled {
                self.scheduleOperations()
            }
        }

        service.didDisconnect = { [weak self] peripheral, error in
            if let initated = self?.disconnectInitiated, initated == true {
                Logger.debug("didDisconnect --> initiated")
                self?.onDisconnectFromDevice?(.success(()))
            } else {
                Logger.debug("didDisconnect --> NOT initiated")
                self?.onFindDevice?(.failure(.didDisconnect(error)))
            }
            self?.resetState()
        }
        
        service.didFailToConnect = { [weak self] peripheral, error in
            self?.onFindDevice?(.failure(.didFailToConnect(error)))
            self?.resetState()
        }
        
        service.didUpdateValueFor = { [weak self] peripheral, value, uuid, error in
            guard let self = self else { return }
            
            if uuid == .SASSerialCharacteristic {
                if let error = error {
                    Logger.error(error.localizedDescription)
                    self.onFindDevice?(.failure(.generic(error)))
                    self.onFundTable?(.failure(.generic(error)))
                    return
                }
                
                if let value = value,
                   let serial = String(data: value, encoding: .utf8) {
                    self.connectedToTable = serial.contains("table")
                    
                    if let amount = self.amountRequested {
                        if amount > 0 {
                            self.onFundTable?(.success(serial))
                            self.amountRequested = nil
                            self.initiateDisconnect()
                        } else {
                            // do nothing here, received amount should come through the .amountCharacteristic
                        }
                    }
                    print(serial)
                    self.onFindDevice?(.success(serial))
                } else {
                    self.onFindDevice?(.failure(.unknown))
                    self.onFundTable?(.failure(.unknown))
                }
            }
            
            if uuid == .amountCharacteristic {
                if let error = error {
                    Logger.error(error.localizedDescription)
                    self.onCashOutTable?(.failure(.generic(error)))
                    return
                }
                
                // return amount
                if let value = value {
                    if let string = String(data: value, encoding: .utf8), let amount = Int(string) {
                        guard amount != -1 else {
                            self.onCashOutTable?(.failure(.dealerCanceledCashout))
                            self.onFundTable?(.failure(.dealerCanceledFunding))
                            self.initiateDisconnect()
                            return
                        }
                        
                        self.onCashOutTable?(.success(amount))
//                        self.initiateDisconnect()
                    }
                }

            }
        }
        
        service.didWriteValueFor = { [weak self] uuid, error in
            guard let self = self else { return }
            
            if uuid == .amountCharacteristic {
                if let error = error {
                    self.onFundTable?(.failure(.generic(error)))
                    return
                }
                
                if let amount = self.amountRequested, amount > 0 {
                    // fundTable case
                    // success, do nothing and wait confirmation over .SASSerialCharacteristic
                }
            }
            
            if uuid == .cancelCharacteristic {
                if let error = error {
                    self.onCancelCashOut?(.failure(.generic(error)))
                    return
                }
                // cashout canceled
                self.onCancelCashOut?(.success(()))
                self.initiateDisconnect()
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
        operationScheduled = true
        
        // setup notifications
        service.notifyDataOperation(.SASSerialCharacteristic, enable: true)
        service.notifyDataOperation(.amountCharacteristic, enable: true)
        
        // start read operations
        service.readDataOperation(for: .SASSerialCharacteristic)
    }
    
    private func writeAmountToTable(amount: Int) {
        guard let data = String(amount).data(using: .utf8)?.base64EncodedData() else { return }
        service.writeDataOperation(data, for: .amountCharacteristic)
    }
    
    private func writeToCancelCashOut() {
        let one: String = "1" // write 1 to the .cancelCharacteristic
        guard let data = one.data(using: .utf8)?.base64EncodedData() else { return }
        service.writeDataOperation(data, for: .cancelCharacteristic)
    }
    
    private func initiateDisconnect() {
        disconnectInitiated = true
        service.cancelCurrentPeripheralConnection()
    }
    
    private func resetState() {
        onFindDevice = nil
        onFundTable = nil
        onCashOutTable = nil
        onCancelCashOut = nil
        onDisconnectFromDevice = nil
        disconnectInitiated = false
        amountRequested = nil
        operationScheduled = false
        connectedToTable = false
    }
}
