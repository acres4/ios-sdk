//
//  AcresBLEError.swift
//
//
//  Created by Jozo Mostarac on 22.07.2022..
//

import Foundation

public enum AcresBLEError: Error {
    case generic(Error)
    case didFailToConnect(Error? = nil)
    case playerCardAlreadyInserted
    case playerCardBusy
    case playerCardTrack1FailedToRecord
    case playerCardTrack2FailedToRecord
    case playerCardInsertFail
    case invalidFormatTrackId1
    case invalidFormatTrackId2
    case dealerCanceledFunding
    case dealerCanceledCashout
    case notConnected
    case notConnectedToTable
    case scanTimeout
    case didDisconnect(Error? = nil)
    case unknown
}

// MARK: - LocalizedError
extension AcresBLEError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .generic(let error):
            return error.localizedDescription
        case .playerCardAlreadyInserted:
            return "Player card is already inserted with this app"
        case .didFailToConnect:
            return "Failed to connect on device"
        case .playerCardBusy:
            return "Player card reader is currently busy"
        case .playerCardTrack1FailedToRecord:
            return "Player card 1 failed to record"
        case .playerCardTrack2FailedToRecord:
            return "Player card 2 failed to record"
        case .playerCardInsertFail:
            return "Player card insertion failed"
        case .dealerCanceledFunding:
            return "Dealer has canceled funding"
        case .dealerCanceledCashout:
            return "Dealer has canceled cashout"
        case .notConnected:
            return "Not connected to any device"
        case .notConnectedToTable:
            return "You are connected to a device, but it's not a table"
        case .scanTimeout:
            return "Failed to find any devices nearly."
        case .didDisconnect:
            return "Device disconnected"
        case .unknown:
            return "Connection error occurred, please try again"
        case .invalidFormatTrackId1:
            return "Card ID is too long for the player card track 1. The data should be less than 79 bytes control characters"
        case .invalidFormatTrackId2:
            return "Card ID is too long for the player card track 2. The data should be less than 40 bytes control characters"
        }
    }
}
