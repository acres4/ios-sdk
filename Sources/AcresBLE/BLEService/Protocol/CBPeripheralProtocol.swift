//
//  CBPeripheralProtocol.swift
//  
//
//  Created by Jozo Mostarac on 21.07.2022..
//

import CoreBluetooth
import Foundation

protocol CBPeripheralProtocol: AnyObject {
  var name: String? { get }
  var state: CBPeripheralState { get }
}

extension CBPeripheralProtocol {
    var identifier: UUID {
        guard let peripheral = self as? CBPeripheral else {
            assert(false)
            return UUID()
        }
        return peripheral.identifier
    }
}
