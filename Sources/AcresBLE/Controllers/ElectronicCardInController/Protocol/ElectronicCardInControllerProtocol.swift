//
//  ElectronicCardInControllerProtocol.swift
//
//
//  Created by Jozo Mostarac on 22.07.2022..
//

import Foundation

public protocol ElectronicCardInControllerProtocol {
    // The insertPlayerCard method cards a player into an EGM. Once called the method will find a BLE device advertising the machine information service with signal strength greater than -65 (or reuse an existing connection from a prior findDevice).
    // The ElectronicCardInController's BLEService will then read the player card busy characteristic.
    // If true the method will return a AcresBLEError to the user, this means there is a physical card inserted into the PID.
    // If false, the method will write the passed string to the .playerCardTrack1Characteristic and return success to the user.
    // If the device is not found it will timeout after CommonControllerProtocol.timeOutValue seconds.
    // The BLE connection stays open after success — the caller must invoke `SlotAndTableControllerProtocol.disconnectFromDevice` when done with the EGM so the EGM isn't held locked to this phone.
    func insertPlayerCard(id: String, cardTrack: CardTrack, completion: @escaping (Result<Void, AcresBLEError>) -> Void)

    // The removePlayerCard method cards out a player from an EGM. Reuses an existing connection if present, otherwise scans/connects. Writes false to the .playerCardInsertCharacteristic and returns success.
    // If the device is not found it will timeout after CommonControllerProtocol.timeOutValue seconds.
    // In case of failure it will return AcresBLEError.
    // The BLE connection stays open after success — the caller must invoke `SlotAndTableControllerProtocol.disconnectFromDevice` when done with the EGM.
    func removePlayerCard(completion: @escaping (Result<Void, AcresBLEError>) -> Void)
}
