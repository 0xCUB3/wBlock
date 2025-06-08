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
}
