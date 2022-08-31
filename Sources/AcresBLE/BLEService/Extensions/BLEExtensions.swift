//
//  BLEExtensions.swift
//  
//
//  Created by Jozo Mostarac on 21.07.2022..
//

import CoreBluetooth
import Foundation

extension CBUUID {
    // Generic Access Service
    static let genericAccessService                 = CBUUID(string: "1800")    // Characteristics for general access.
    static let txPowerLevelCharacteristic           = CBUUID(string: "2A07")    // Read the power level set on the BLE ranges [-800,80].
    static let deviceNameCharacteristic             = CBUUID(string: "2A00")    // Name of the device.
    static let appearanceCharacteristic             = CBUUID(string: "2A01")    // External appearance of the device.
    
    // Device Information Service
    static let deviceInformationService             = CBUUID(string: "180A")    // Characteristics for manufacturer and/or vendor information.
    static let manufacturerNameCharacteristic       = CBUUID(string: "2A29")    // Constant value (Acres).
    static let modelNumberCharacteristic            = CBUUID(string: "2A24")    // The model number assigned by Acres.
    static let systemIdCharacteristic               = CBUUID(string: "2A23")    // The system ID assigned by Acres.
    
    // Machine Information Service
    static let machineInformationService            = CBUUID(string: "C83FE52E-0AB5-49D9-9817-98982B4C48A3")    // Characteristics for EGM information.
    static let SASSerialCharacteristic              = CBUUID(string: "9D77E2CF-5D20-44EA-8D2F-A221B976C605")    // The slot machine serial number.
    static let assetNumberCharacteristic            = CBUUID(string: "D77A787D-E75D-4370-8cAC-6DCFE37DBB92")    // The Asset Number of the EGM.
    static let denominationCharacteristic           = CBUUID(string: "7B9432C6-465A-40fA-A13B-03544B6F0742")    // The Current denomination set on the EGM.
    static let locationCharacteristic               = CBUUID(string: "42C458D7-86B9-4ED8-B57E-1352C7F5100A")    // The Location of the EGM.
    static let gameIdCharacteristic                 = CBUUID(string: "39B6BCC9-9DA0-46DF-84FE-8B0BA43F8AE9")    // The Game ID of the EGM.
    static let propertyIdCharacteristic             = CBUUID(string: "23C6B6E0-100A-41B4-81A5-5CC8C98E2A0A")    // The Property ID where EGM located.
    
    // Player Presence Service
    static let playerPresenceService                = CBUUID(string: "7C056092-31D9-4807-85B1-ADC272218DF9")    // Characteristics to card a player into the EGM.
    static let playerCardBusyCharacteristic         = CBUUID(string: "1179974A-EE22-4DED-A842-78750E977BCF")    // If true, then a mechanical card is inserted.
    static let playerCardTrack1Characteristic       = CBUUID(string: "C3F67C88-5D44-4F5B-83AF-896F377AB6E7")    // The player card track1 data including control characters.
    static let playerCardTrack2Characteristic       = CBUUID(string: "02F2C17B-751F-4F2E-816C-8D67622614DA")    // The player card track2 data including control characters.
    static let playerCardInsertCharacteristic       = CBUUID(string: "7147C04E-F8E5-419D-B072-F50C45A5A431")    // Write to insert or remove ‘card’.
    
    
    // Unknown service
    static let amountCharacteristic                 = CBUUID(string: "2D488603-34B2-4640-9831-BDE5D0EEFF28")    // Write fund amount to ask for transfer permission. Write zero to ask for cash-out.
    static let cancelCharacteristic                 = CBUUID(string: "DA9E1DA3-684C-4178-B140-9D17E3732769")    // Write 1 to cancel cash-out. Exists only on table.
}

extension Data {
    var hexString: String {
        return "[ " + self.reduce(""){$0 + String(format: "%02X ", $1)} + "]"
    }
}

extension UInt8 {
    var toBool: Bool {
        return self == 0x01 ? true : false
    }
}

extension Bool {
    var toUInt8: UInt8 {
        return self ? 0x01 : 0x00
    }
}

func byteArray<T>(from value: T) -> [UInt8] where T: FixedWidthInteger {
    withUnsafeBytes(of: value.bigEndian, Array.init)
}
