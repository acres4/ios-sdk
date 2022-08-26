//
//  AcresBLEManager.swift
//  
//
//  Created by Jozo Mostarac on 22.07.2022..
//

import Foundation

public class AcresBLE {
    public static var shared = AcresBLE()
    
    private let service: BLEService
    
    init () {
        self.service = BLEService()
        self.electronicCardInController = ElectronicCardInController(service: service)
        self.slotAndTableController = SlotAndTableController(service: service)
    }
    
    public var electronicCardInController: ElectronicCardInControllerProtocol
    public var slotAndTableController: SlotAndTableControllerProtocol
}
