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
    // On success the connection is closed before the completion handler returns, so the EGM is released even if the player walks away with the card still inserted.
    func insertPlayerCard(id: String, cardTrack: CardTrack, completion: @escaping (Result<Void, AcresBLEError>) -> Void)

    // The removePlayerCard method cards out a player from an EGM. It scans for the EGM and connects fresh (insertPlayerCard already disconnected on its success), writes false to the .playerCardInsertCharacteristic, then disconnects again before returning success.
    // If the device is not found it will timeout after CommonControllerProtocol.timeOutValue seconds.
    // In case of failure it will return AcresBLEError.
    func removePlayerCard(completion: @escaping (Result<Void, AcresBLEError>) -> Void)
}
