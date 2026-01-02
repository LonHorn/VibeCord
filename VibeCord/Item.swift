//
//  Item.swift
//  VibeCord
//
//  Created by Александр Гарбушка on 02/01/2026.
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
