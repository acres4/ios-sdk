# AcresBLE

The AcresBLE SDK is meant to make Bluetooth integration as easy as possible for our
technology partners. This framework includes functionality to initiate funding to/from slots and
tables and electronic player carding to our card reader.

# SDK Structure
SDK is separated into two controller, each one consisting of interconnected methods used for simple communication with Acres BLE devices.
`ElectronicCardInController` is used for communication with card reader device for the purpose of inserting and removing player card via BLE.
`SlotAndTableController` is used for communication with slots and tables. Methods `fundTable`, `cashOutTable` and `cancelCashOut` are only available for tables.

### ElectronicCardInController
The `insertPlayerCard` method cards a player into an EGM. Once called the method will find a BLE device advertising the machine information service with signal strength greater than -65. The `ElectronicCardInController`'s `BLEService` will then read the player card busy characteristic. If `true` the method will return a `AcresBLEError` to the user, this means there is a physical card inserted into the PID. If `false`, the method will write the passed string to the `.playerCardTrack1Characteristic` and return serial string via the success case to the user. If the device is not found it will timeout after `CommonControllerProtocol.timeOutValue` seconds.

``` swift
func insertPlayerCard(id: String, cardTrack: CardTrack, completion: @escaping (Result<Void, AcresBLEError>) -> Void)
```
  
The `removePlayerCard ` method cards out a player from an EGM. Once called the method will write `false` to the `.playerCardInsertCharacteristic`. After writing it will return success case to the user.In case of failure it will return AcresBLEError.
    
``` swift
func removePlayerCard(completion: @escaping (Result<Void, AcresBLEError>) -> Void)
```

### SlotAndTableController
The `findDevice` method searches for a BLE device that is advertising a `.machineInformationService` and has a signal strength of **greater than -65**. The `SlotAndTableController`'s `BLEService` will then read from the `.SASSerialCharacteristic`. Once read the method will return the `string` containing serial back to the user or the `AcresBLEError` in case of failure.
    
``` swift
func findDevice(completion: @escaping (Result<String, AcresBLEError>) -> Void)
```
    
The `fundTable` method is used by the client if the returned string from `findDevice` method contains **“table”**. When funding a table game we must first ask for permission to transfer from the dealer, and it is done internally inside SDK by writing a transfer amount to the `.amountCharacteristic`. Once accepted by the dealer SDK will receive a notification over the `.SASSerialCharacteristic` and return the string containing serial back to the user or the `AcresBLEError` in case of failure.
(only available for tables)

``` swift
func fundTable(amount: Int, completion: @escaping (Result<String, AcresBLEError>) -> Void)
```

The `cashOutTable` method notifies the dealer of an impending cash-out by writing a **zero** to the `.amountCharacteristic`. Once this is done the dealer will be prompted to enter a cash-out amount, and player will then receive notifications over both the `.amountCharacteristic` and `.SASSerialCharacteristic` (both will be handled inside SKD). The user will then get back cash-out amount and show a notification to the player to accept the suggested cash-out amount and finish the transaction or cancel it with `cancelCashOut` method. In case of failure method will return `AcresBLEError`.
(only available for tables)

``` swift
func cashOutTable(completion: @escaping (Result<Int, AcresBLEError>) -> Void)
```

The `cancelCashOut` method is used to reject the cash-out amount suggested by the dealer.
(only available for tables)

``` swift
func cancelCashOut(completion: @escaping (Result<Void, AcresBLEError>) -> Void)
```    
    
The `disconnectFromDevice` method initiates disconnecting from connected device.
    
``` swift
func disconnectFromDevice(completion: @escaping (Result<Void, AcresBLEError>) -> Void)
```

# Example of usage

Example of usage in an app using SwiftUI framework with MVVM architecture.
Example of SDK's implementation in app can be found in `Example` folder.
To run the example app on real device **your own team should be selected** inside Xcode's Signing & Capabilities section.

```swift
import AcresBLE

class ViewModel: ObservableObject {
    private let errorHandler: ErrorHandler = ErrorHandler.shared
    private let electronicCardInController: ElectronicCardInControllerProtocol = AcresBLE.shared.electronicCardInController
    @Published var state: State = .removed
    
    @Published var cardTrack: CardTrack = .one
    @Published var cardID: String = ""

    /* ... */
    
    func insertPlayerCard() {
        state = .inserting
        electronicCardInController.insertPlayerCard(id: cardID, cardTrack: cardTrack) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success():
                self.state = .inserted
            case .failure(let error):
                self.state = .removed
                self.errorHandler.errorMessage = error.errorDescription
            }
        }
    }
}
```

# Installation
AcresBLE SDK supports installation with SPM.

Open Xcode and your project, click File / Swift Packages / Add package dependency... . In the textfield "Enter package repository URL", write URL of the location containing SDK repository and press Next twice.
