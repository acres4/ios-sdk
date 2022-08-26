//
//  ErrorHandler.swift
//  AcresBLEDemo
//
//  Created by Jozo Mostarac on 19.08.2022..
//

import Foundation

class ErrorHandler: ObservableObject {
    static let shared = ErrorHandler()
    
    @Published var isErrorPresented: Bool = false
    @Published var errorMessage: String? {
        didSet {
            self.isErrorPresented = (self.errorMessage != nil)
        }
    }
}
