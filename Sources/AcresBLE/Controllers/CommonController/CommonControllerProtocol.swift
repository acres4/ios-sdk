//
//  CommonControllerProtocol.swift
//  
//
//  Created by Jozo Mostarac on 22.07.2022..
//

import Foundation

protocol CommonControllerProtocol {
    // Instance of BLEServiceProtocol used by controller to perform BLE actions.
    var service: BLEServiceProtocol { get set }
        
    // Cancellable task used by scheduleTimeout(task: DispatchWorkItem) method for scheduling scaning timeout.
    var timeOutTask: DispatchWorkItem { get set }
    
    // Start scanning and connect to CBPeripheralProtocol conforming rssiLimit. Register Discovered callback on BLEServiceProtocol.
    // Skip scannig if BLEServiceProtocol is already connected to CBPeripheralProtocol.
    func startScan()
    
    // Initialize connection to CBPeripheralProtocol.
    // Register DidDiscoverCharacteristicsFor, DidDisconnect and DidFailToConnect callbacks on BLEServiceProtocol.
    func connect(to device: CBPeripheralProtocol)
    
    // Stop scanning for CBPeripheralProtocol
    func stopScan()
    
    // Register DidUpdateValueFor and DidWriteValueFor callbacks on BLEServiceProtocol.
    func setupConnection()
}

extension CommonControllerProtocol {
    // Set minimal RSSI nedeed to initialize connection.
    internal var rssiLimit: Int {
        return -65
    }
    
    // Set timeout value for scanning operations.
    internal var timeOutValue: Double {
        return 10
    }
    
    internal func scheduleTimeout(task: DispatchWorkItem) {
        DispatchQueue.main.asyncAfter(deadline: .now() + timeOutValue, execute: task)
    }
}
