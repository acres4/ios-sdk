//
//  SlotAndTableControllerViewModel.swift
//  AcresBLEDemo
//
//  Created by Jozo Mostarac on 19.08.2022..
//

import Foundation
import AcresBLE

class SlotAndTableControllerViewModel: ObservableObject {
    enum State {
        case disconnected, scanning, working, fund, funding, funded, cashingOut, cashingOutConfirmation, cashedOut, cashOutCanceling, cashOutCanceled
    }
    
    enum FindDeviceMode {
        case fund, cashout, cancelCashOut
    }
    
    private let errorHandler: ErrorHandler = ErrorHandler.shared
    private let slotAndTableController: SlotAndTableControllerProtocol = AcresBLE.shared.slotAndTableController

    @Published var state: State = .disconnected {
        didSet { print("STATE IS: \(state)") }
    }
    @Published var sas: String? {
        didSet { connectedToTable = sas?.contains("table") ?? false }
    }
    @Published var connectedToTable: Bool = false
    @Published var cashOutAmount: Int?
    
    // MARK: - Slot and table controller
    func findDevice(_ mode: FindDeviceMode) {
        state = .scanning
        
        slotAndTableController.findDevice { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let sas):
                print("DEBUG slotAndTableController.findDevice success")
                self.sas = sas
                
                guard self.state == .scanning else { return }
                
                switch mode {
                case .fund:
                    self.state = .fund
                case .cashout:
                    self.cashOutTable()
                case .cancelCashOut:
                    self.cancelCashOut()
                }
            case .failure(let error):
                print("DEBUG slotAndTableController.findDevice error: \(error)")
                self.errorHandler.errorMessage = error.errorDescription
                self.sas = nil
                self.setInitialState()
            }
        }
    }
    
    func disconnectFromDevice() {
        slotAndTableController.disconnectFromDevice { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success():
                print("DEBUG slotAndTableController.disconnectFromDevice success")
                self.sas = nil
            case .failure(let error):
                print("DEBUG slotAndTableController.disconnectFromDevice error: \(error)")
                self.errorHandler.errorMessage = error.errorDescription
            }
            
            self.state = .disconnected
        }
    }
    
    func fundTable(amount: Int) {
        self.state = .funding
        slotAndTableController.fundTable(amount: amount) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let sas):
                print("DEBUG slotAndTableController.fundTable success, sas: \(sas)")
                self.state = .funded
                self.setInitialState(delayed: true)
            case .failure(let error):
                print("DEBUG slotAndTableController.fundTable error: \(error)")
                self.errorHandler.errorMessage = error.errorDescription
                self.setInitialState()
            }
        }
    }
    
    func cashOutTable() {
        self.state = .cashingOut
        slotAndTableController.cashOutTable { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let amount):
                print("DEBUG slotAndTableController.cashOutTable success, amount: \(amount)")
                self.cashOutAmount = amount
                self.state = .cashingOutConfirmation
            case .failure(let error):
                print("DEBUG slotAndTableController.cashOutTable error: \(error)")
                self.errorHandler.errorMessage = error.errorDescription
                self.setInitialState()
            }
        }
    }
    
    func cancelCashOut() {
        self.state = .cashOutCanceling
        slotAndTableController.cancelCashOut { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                print("DEBUG slotAndTableController.cancelCashOut success")
                self.cashOutAmount = nil
                self.state = .cashOutCanceled
                self.setInitialState(delayed: true)
            case .failure(let error):
                print("DEBUG slotAndTableController.cancelCashOut error: \(error)")
                self.errorHandler.errorMessage = error.errorDescription
                self.setInitialState()
            }
        }
    }
    
    func acceptCashOut() {
        cashOutAmount = nil
        state = .cashedOut
        setInitialState(delayed: true)
    }
    
    private func setInitialState(delayed: Bool = false) {
        if delayed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.sas = nil
                self.state = .disconnected
            }
        } else {
            self.sas = nil
            self.state = .disconnected
        }
    }
}
