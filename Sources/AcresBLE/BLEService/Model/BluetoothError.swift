//
//  BluetoothError.swift
//  
//
//  Created by Jozo Mostarac on 21.07.2022..
//

import Foundation

enum BluetoothError: Swift.Error {
  case cbError(Error)
  case permissionDenied
  case bluetoothDisabled
  case bluetoothUnsupported
  case bluetoothResetting
  case deviceNotConnected
  case unsupportedDevice
  case writeValueError
  case manualSessionStartedError
  case unknown
}

// MARK: - LocalizedError
extension BluetoothError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .cbError(let error):
      return error.localizedDescription
    case .permissionDenied:
      return "Open Settings and enable Bluetooth access"
    case .bluetoothDisabled:
      return "Turn Bluetooth on to search a device"
    case .bluetoothUnsupported:
      return "Bluetooth is not supported on your device, connection will not be possible"
    case .bluetoothResetting:
      return "Bluetooth is being reset, please try again"
    case .deviceNotConnected:
      return "No connected devices, please connect a device and try again"
    case .unsupportedDevice:
      return "This peripheral is not fully supported"
    case .writeValueError:
      return "Could not send new value to device"
    case .manualSessionStartedError:
      return "This setting cannot be adjusted while a session is in progress. To change this setting, please stop the session first."
    case .unknown:
      return "Connection error occurred, please try again"
    }
  }
}
