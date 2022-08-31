//
//  CardControllerViewModel.swift
//  AcresBLEDemo
//
//  Created by Jozo Mostarac on 28.07.2022..
//

import Foundation
import AcresBLE

class CardControllerViewModel: ObservableObject {
    enum State {
        case removing, removed, inserting, inserted
    }
    
    private let errorHandler: ErrorHandler = ErrorHandler.shared
    private let electronicCardInController: ElectronicCardInControllerProtocol = AcresBLE.shared.electronicCardInController
    
    @Published var state: State = .removed {
        didSet { print("STATE IS: \(state)") }
    }
    
    // MARK: - Electronic card-in controller
    
    func insertPlayerCard(id: String = "") {
        state = .inserting
        electronicCardInController.insertPlayerCard(id: id) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success():
                print("DEBUG electronicCardInController.insertPlayerCard success")
                self.state = .inserted
            case .failure(let error):
                print("DEBUG electronicCardInController.insertPlayerCard error: \(error)")
                self.state = .removed
                self.errorHandler.errorMessage = error.errorDescription
            }
        }
    }
    
    func removePlayerCard() {
        guard state == .inserted else { return }
        
        state = .removing
        electronicCardInController.removePlayerCard { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success():
                print("DEBUG electronicCardInController.removePlayerCard success")
                self.state = .removed
            case .failure(let error):
                print("DEBUG electronicCardInController.removePlayerCard error: \(error)")
                self.state = .inserted
                if case .notConnected = error {
                    self.state = .removed
                }
                self.errorHandler.errorMessage = error.errorDescription
            }
        }
    }
}
