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
    public var lastUpdated: Date?
    public var languages: [String] = []
    public var trustLevel: String? = nil
    public var etag: String? = nil
    public var serverLastModified: String? = nil
    public var limitExceededReason: String? = nil // Reason why filter was auto-disabled due to rule limits

    public init(id: UUID = UUID(),
                name: String,
                url: URL,
                category: FilterListCategory,
                isSelected: Bool = false,
                description: String = "",
                version: String = "",
                sourceRuleCount: Int? = nil,
                lastUpdated: Date? = nil,
                languages: [String] = [],
                trustLevel: String? = nil,
                etag: String? = nil,
                serverLastModified: String? = nil,
                limitExceededReason: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.category = category
        self.isSelected = isSelected
        self.description = description
        self.version = version
        self.sourceRuleCount = sourceRuleCount
        self.lastUpdated = lastUpdated
        self.languages = languages
        self.trustLevel = trustLevel
        self.etag = etag
        self.serverLastModified = serverLastModified
        self.limitExceededReason = limitExceededReason
    }
    
    /// Returns a formatted string for the last updated date
    public var lastUpdatedFormatted: String? {
        guard let lastUpdated = lastUpdated else { return nil }
        
        let formatter = DateFormatter()
        let now = Date()
        let calendar = Calendar.current
        
        if calendar.isDate(lastUpdated, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "Today at \(formatter.string(from: lastUpdated))"
        } else if let daysDifference = calendar.dateComponents([.day], from: lastUpdated, to: now).day, daysDifference < 7 {
            formatter.dateFormat = "EEEE 'at' h:mm a"
            return formatter.string(from: lastUpdated)
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: lastUpdated)
        }
    }
}
