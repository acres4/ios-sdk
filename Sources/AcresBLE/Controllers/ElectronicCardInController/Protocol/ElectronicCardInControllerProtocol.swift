//
//  ElectronicCardInControllerProtocol.swift
//
//
//  Created by Jozo Mostarac on 22.07.2022..
//

import Foundation

public protocol ElectronicCardInControllerProtocol {
    // The insertPlayerCard method cards a player into an EGM. Once called the method will find a BLE device advertising the machine information service with signal strength greater than -65.
    // The ElectronicCardInController's BLEService will then read the player card busy characteristic.
    // If true the method will return a AcresBLEError to the user, this means there is a physical card inserted into the PID.
    // If false, the method will write the passed string to the .playerCardTrack1Characteristic and return serial string via the success case to the user.
    // If the device is not found it will timeout after CommonControllerProtocol.timeOutValue seconds.
    func insertPlayerCard(id: String, cardTrack: CardTrack, completion: @escaping (Result<Void, AcresBLEError>) -> Void)

    // The removePlayerCard method cards out a player from an EGM. Once called the method will write false to the .playerCardInsertCharacteristic. After writing it will return success case to the user.
    // In case of failure it will return AcresBLEError.
    func removePlayerCard(completion: @escaping (Result<Void, AcresBLEError>) -> Void)
}
