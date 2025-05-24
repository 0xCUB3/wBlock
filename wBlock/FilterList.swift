//
//  FilterListCategory.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import Combine
import Foundation

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

struct FilterList: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var url: URL
    var category: FilterListCategory
    var isSelected: Bool = false
    var description: String = ""
    var version: String = ""
    var sourceRuleCount: Int?
}
