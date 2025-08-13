//
//  FilterList.swift
//  wBlock
//
//  Created by Alexander Skula on 5/25/25.
//

import Foundation
import wBlockCoreService

public struct FilterList: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var category: FilterListCategory
    public var isSelected: Bool = false
    public var description: String = ""
    public var version: String = ""
    public var sourceRuleCount: Int?
    
    public init(id: UUID = UUID(), name: String, url: URL, category: FilterListCategory, isSelected: Bool = false, description: String = "", version: String = "", sourceRuleCount: Int? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.category = category
        self.isSelected = isSelected
        self.description = description
        self.version = version
        self.sourceRuleCount = sourceRuleCount
    }
}
