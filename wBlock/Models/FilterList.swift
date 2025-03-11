//
//  FilterList.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//

import Foundation
import Combine

enum FilterListCategory: String, CaseIterable, Identifiable, Codable {
    case all = "All"
    case ads = "Ads"
    case privacy = "Privacy"
    case security = "Security"
    case multipurpose = "Multipurpose"
    case annoyances = "Annoyances"
    case experimental = "Experimental"
    case custom = "Custom"
    case foreign = "Foreign"
    var id: String { self.rawValue }
}

struct FilterList: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let url: URL
    let category: FilterListCategory
    var isSelected: Bool = false
    var description: String = ""
    var version: String = ""
}
