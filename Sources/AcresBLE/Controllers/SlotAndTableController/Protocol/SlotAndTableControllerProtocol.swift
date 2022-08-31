//
//  SlotAndTableControllerProtocol.swift
//  
//
//  Created by Jozo Mostarac on 22.07.2022..
//

import Foundation

public protocol SlotAndTableControllerProtocol {
    // The findDevice method searches for a BLE device that is advertising a .machineInformationService and has a signal strength of greater than -65.
    // The SlotAndTableController's BLEService will then read from the .SASSerialCharacteristic.
    // Once read the method will return the string containg serial back to the user or the AcresBLEError in case of failure.
    func findDevice(completion: @escaping (Result<String, AcresBLEError>) -> Void)
    
    // The fundTable method is used by the client if the returned string from findDevice method contains “table”.
    // When funding a table game we must first ask for permission to transfer from the dealer, and it is done internally inside SDK by writing a transfer amount to the .amountCharacteristic.
    // Once accepted by the dealer SDK will receive a notification over the .SASSerialCharacteristic and return the string containing serial back to the user or the AcresBLEError in case of failure.
    // (only available for tables)
    func fundTable(amount: Int, completion: @escaping (Result<String, AcresBLEError>) -> Void)
    
    // The cashOutTable method notifies the dealer of an impending cash-out by writing a zero to the .amountCharacteristic.
    // Once this is done the dealer will be prompted to enter a cash-out amount and player will then receive notifications over both the .amountCharacteristic and .SASSerialCharacteristic (both will be handled inside SKD).
    // The user will then get back cash-out amount and show a notification to the player to accept the suggested cash-out amount and finish the transaction or cancel it with cancelCashOut method.
    // In case of failure method will return AcresBLEError.
    // (only available for tables)
    func cashOutTable(completion: @escaping (Result<Int, AcresBLEError>) -> Void)
    
    // The cancelCashOut method is used to reject the cash-out amount suggested by the dealer.
    // (only available for tables)
    func cancelCashOut(completion: @escaping (Result<Void, AcresBLEError>) -> Void)
    
    // The disconnectFromDevice method initiates disconnecting from connected device.
    func disconnectFromDevice(completion: @escaping (Result<Void, AcresBLEError>) -> Void)
}
