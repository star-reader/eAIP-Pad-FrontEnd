//
//  Item.swift
//  eAIP Pad
//
//  Created by usagi on 2025/10/30.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
