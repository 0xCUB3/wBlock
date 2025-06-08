//
//  Item.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
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
