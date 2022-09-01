//
//  BLEService.swift
//  
//
//  Created by Jozo Mostarac on 21.07.2022..
//

import CoreBluetooth
import Foundation

class BLEService: NSObject, BLEServiceProtocol, PeripheralIdentificationProtocol {
    var stateError: StateBleError = { _ in }
    var discovered: Discovered = { _, _, _ in }
    var didDisconnect: DidDisconnect = { _, _ in }
    var didFailToConnect: DidFailToConnect = { _, _ in }
    var didDiscoverCharacteristicsFor: DidDiscoverCharacteristicsFor = { _ in }
    var didUpdateValueFor: DidUpdateValueFor = { _, _, _, _ in }
    var didWriteValueFor: DidWriteValueFor = { _, _ in }
    
    private let operationQueue: OperationQueue
    private var peripheral: CBPeripheral?
    private let central = BLECentral.shared
    
    init(operationQueue: OperationQueue = OperationQueue()) {
        self.operationQueue = operationQueue
        super.init()
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .utility
        central.add(delegate: self)
        Logger.debug("BLEService init")
    }

    var isOn: Bool { central.centralManager.state == .poweredOn }
    var isAuthorized: Bool { CBCentralManager.authorization == .allowedAlways }

    func checkBluetoothState() {
        switch (central.centralManager.state, isAuthorized) {
        case (.unknown, _), (.resetting, _):
            break  // wait for notifications
        case (.poweredOn, true):
            stateError(nil)
        case (.poweredOff, _):
            stateError(.bluetoothDisabled)
        default:
            stateError(.permissionDenied)
        }
    }

    func startScanning(allowDuplicates: Bool) {
        let options = allowDuplicates ? [CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)] : nil
        central.centralManager.scanForPeripherals(withServices: [.machineInformationService], options: options)
    }

    func stopScanning() {
        central.centralManager.stopScan()
    }

    func isScanning() -> Bool {
        return central.centralManager.isScanning
    }

    func connect(to device: CBPeripheralProtocol) {
        guard let device = device as? CBPeripheral else { return }
        
        if let peripheral = peripheral,
            peripheral.state != .disconnected {
            return
        }
        
        peripheral = device
        central.centralManager.connect(device, options: nil)
        Logger.debug("connect to device: \(String(describing: peripheral?.identifier))")
    }

    func cancelCurrentPeripheralConnection() {
        guard let device = getPeripheral() else { return }
        central.centralManager.cancelPeripheralConnection(device)
    }

    func cancelPeripheralConnection(peripheral: CBPeripheralProtocol) {
        guard let peripheralToCancel = peripheral as? CBPeripheral else { return }
        central.centralManager.cancelPeripheralConnection(peripheralToCancel)
    }

    func getPeripheral() -> CBPeripheral? {
        return peripheral
    }

    func suspendQueue(_ bool: Bool) {
        operationQueue.isSuspended = bool
    }
    
    func cancelAllOperations() {
        operationQueue.cancelAllOperations()
        suspendQueue(false)
    }

    func getDataFor(_ uuid: CBUUID) -> Data? {
        guard let characteristic = getCharacteristic(uuid) else { return nil }
        return characteristic.value
    }

    func operation(block: @escaping (() -> ())) {
        operationQueue.addOperation {
            block()
        }
    }
    
    func writeDataOperation(_ data: Data, for uuid: CBUUID) {
        operationQueue.addOperation { [weak self] in
            self?.writeData(data, for: uuid)
        }
    }

    func notifyDataOperation(_ uuid: CBUUID, enable: Bool) {
        operationQueue.addOperation { [weak self] in
            self?.notifyDataFor(uuid, enable: enable)
        }
    }

    func readDataOperation(for uuid: CBUUID) {
        operationQueue.addOperation { [weak self] in
            self?.readDataFor(uuid)
        }
    }

    private func getCharacteristic(_ uuid: CBUUID) -> CBCharacteristic? {
        return getPeripheral()?.services?
            .map { $0.characteristics }
            .compactMap { $0 }
            .flatMap { $0 }
            .first(where: { $0.uuid == uuid })
    }

    private func notifyDataFor(_ uuid: CBUUID, enable: Bool) {
        if let peripheral = getPeripheral(), let characteristic = getCharacteristic(uuid) {
            peripheral.setNotifyValue(enable, for: characteristic)
            suspendQueue(true)
            Logger.debug("notifyDataFor \(uuid) SUSPENDED")
            return
        }
        suspendQueue(false)
        Logger.debug("OP: notifyDataFor error: \(uuid.uuidString)")
        Logger.error("Can't find characteristic \(uuid.uuidString)")
    }

    private func readDataFor(_ uuid: CBUUID) {
        if let peripheral = getPeripheral(), let characteristic = getCharacteristic(uuid) {
            Logger.debug("OP: readDataFor: \(characteristic.uuid.uuidString)")
            peripheral.readValue(for: characteristic)
            suspendQueue(true)
            Logger.debug("readDataFor \(uuid) SUSPENDED")
            return
        }
        suspendQueue(false)
        Logger.error("Can't find characteristic \(uuid.uuidString)")
    }

    private func writeData(_ data: Data, for uuid: CBUUID) {
        if let peripheral = getPeripheral(), let characteristic = getCharacteristic(uuid) {
            Logger.debug("OP: writeData \(characteristic.uuid.uuidString) : \(data.hexString)")
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            suspendQueue(true)
            Logger.debug("writeData \(uuid) SUSPENDED")
            return
        }
        suspendQueue(false)
        Logger.error("Can't find characteristic \(uuid.uuidString)")
    }
}
// MARK: - CBCentralManagerDelegate
extension BLEService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        stateError(central.state.bluetoothErrorState)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discovered(
            peripheral,
            BLEAdvertisingData(data: nil, name: nil),
            RSSI.intValue)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        didDisconnect(peripheral, error)
        cancelAllOperations()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        didFailToConnect(peripheral, error)
        cancelAllOperations()
    }

}
// MARK: - CBPeripheralDelegate
extension BLEService: CBPeripheralDelegate {

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?) {

        guard let services = peripheral.services else { return }

        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?) {

        guard let services = peripheral.services else { return }
        
        guard let index = services.firstIndex(of: service) else { return }

        if index == services.count - 1 {
            didDiscoverCharacteristicsFor(peripheral)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?) {
        var btError: BluetoothError? = nil
        error.map { btError = .cbError($0) }
            
        suspendQueue(false)
        didUpdateValueFor(peripheral, characteristic.value, characteristic.uuid, btError)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?) {

        suspendQueue(false)
        didWriteValueFor(characteristic.uuid, error)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?) {

        suspendQueue(false)
    }
}

private extension CBManagerState {
    var bluetoothErrorState: BluetoothError? {
        switch self {
        case .poweredOff: return .bluetoothDisabled
        case .unknown: return .unknown
        case .resetting: return .bluetoothResetting
        case .unsupported: return .bluetoothUnsupported
        case .unauthorized: return .permissionDenied
        case .poweredOn: return nil
        @unknown default: return .unknown
        }
    }
}
