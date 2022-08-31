//
//  BLEAdvertisingData.swift
//  
//
//  Created by Jozo Mostarac on 21.07.2022..
//

import Foundation

class BLEAdvertisingData {
    let data: Data?
    let name: String?
    
    init?(data: Data?, name: String? = nil) {
        guard let advData = data else { return nil }
        
        self.data = advData
        self.name = name
    }
}
