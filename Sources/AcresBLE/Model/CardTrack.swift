//
//  File.swift
//
//
//  Created by Josip Glasovac on 03.11.2022..
//

import Foundation
import CoreBluetooth

public enum CardTrack: Int, CaseIterable {
    case one = 1
    case two = 2

    public var name: String {
        "Track \(self.rawValue)"
    }

    // Values from the documentation about characteristics
    var maxBytesSizeToWrite: Int {
        switch self {
        case .one:
            return 79
        case .two:
            return 40
        }
    }

    var maxBytesSizeToWriteError: AcresBLEError {
        switch self {
        case .one:
            return AcresBLEError.invalidFormatTrackId1
        case .two:
            return AcresBLEError.invalidFormatTrackId2
        }
    }

    var characteristicNumber: CBUUID {
        switch self {
        case .one:
            return CBUUID.playerCardTrack1Characteristic
        case .two:
            return CBUUID.playerCardTrack2Characteristic
        }
    }
}
