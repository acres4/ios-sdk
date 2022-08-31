//
//  BLECentral.swift
//  
//
//  Created by Jozo Mostarac on 21.07.2022..
//

import CoreBluetooth
import Foundation

class BLECentral: NSObject {
    static let shared = BLECentral()
    var centralManager: CBCentralManager!
    
    typealias BLECentralDelegate = CBCentralManagerDelegate & CBPeripheralDelegate & PeripheralIdentificationProtocol
    
    var delegates = [BLECentralDelegate]()
    
    private override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }
    
    func add(delegate: BLECentralDelegate) {
        guard !delegates.contains(where: {
            (delegate.getPeripheral()?.identifier ?? UUID()) == $0.getPeripheral()?.identifier
        }) else {
            assert(false)
            return
        }
        Logger.debug("CBCentralManagerDelegate delegate added \(delegate.getPeripheral()?.name ?? "Unknown")")
        delegates.append(delegate)
    }
}

extension BLECentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegates.forEach( { $0.centralManagerDidUpdateState(central) } )
    }
    
    func centralManager( _ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber
    ) {
        Logger.debug("SCAN: \(peripheral.identifier) : \(RSSI) dBm")
        delegates.forEach { $0.centralManager?(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI) }
    }

    func centralManager( _ central: CBCentralManager,
                         didConnect peripheral: CBPeripheral
    ) {
        delegates.forEach { delegate in
            if delegate.getPeripheral()?.identifier == peripheral.identifier {
                peripheral.delegate = delegate
                peripheral.discoverServices(nil)
            }
        }
    }
    
    func centralManager( _ central: CBCentralManager,
                         didDisconnectPeripheral peripheral: CBPeripheral,
                         error: Error?
    ) {
        delegates.forEach { delegate in
            if delegate.getPeripheral()?.identifier == peripheral.identifier {
                delegate.centralManager?(central, didDisconnectPeripheral: peripheral, error: error)
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        delegates.forEach { delegate in
            if delegate.getPeripheral()?.identifier == peripheral.identifier {
                delegate.centralManager?(central, didFailToConnect: peripheral, error: error)
            }
        }
    }
}
