//
//  BLEServiceProtocol.swift
//  
//
//  Created by Jozo Mostarac on 21.07.2022..
//

import CoreBluetooth
import Foundation

typealias StateBleError = (_ error: BluetoothError?) -> ()
typealias Discovered = (_ peripheral: CBPeripheralProtocol, _ data: BLEAdvertisingData?, _ rssi: Int) -> ()
typealias DidDisconnect = (_ peripheral: CBPeripheralProtocol, _ error: Error?) -> ()
typealias DidFailToConnect = (_ peripheral: CBPeripheralProtocol, _ error: Error?) -> ()
typealias DidDiscoverCharacteristicsFor = (_ peripheral: CBPeripheralProtocol) -> ()
typealias DidUpdateValueFor = (_ peripheral: CBPeripheralProtocol, _ vaule: Data?, _ uuid: CBUUID, _ error: BluetoothError?) -> ()
typealias DidWriteValueFor = (_ uuid: CBUUID, _ error: Error?) -> ()

protocol BLEServiceProtocol: AnyObject, PeripheralIdentificationProtocol {
    var stateError: StateBleError { get set }
    var discovered: Discovered { get set }
    var didDisconnect: DidDisconnect { get set }
    var didFailToConnect: DidFailToConnect { get set }
    var didDiscoverCharacteristicsFor: DidDiscoverCharacteristicsFor { get set }
    var didUpdateValueFor: DidUpdateValueFor { get set }
    var didWriteValueFor: DidWriteValueFor { get set }
    
    var isOn: Bool { get }
    var isAuthorized: Bool { get }
    
    func getDataFor(_ uuid: CBUUID) -> Data?
    func checkBluetoothState()
    func startScanning(allowDuplicates: Bool)
    func stopScanning()
    func isScanning() -> Bool
    func connect(to device: CBPeripheralProtocol)
    func cancelCurrentPeripheralConnection()
    func cancelPeripheralConnection(peripheral: CBPeripheralProtocol)
    func operation(block: @escaping (() -> ()))
    func writeDataOperation(_ data: Data, for uuid: CBUUID)
    func notifyDataOperation(_ uuid: CBUUID, enable: Bool)
    func readDataOperation(for uuid: CBUUID)
    func suspendQueue(_ bool: Bool)
    func cancelAllOperations()
}

protocol PeripheralIdentificationProtocol {
    func getPeripheral() -> CBPeripheral?
}
