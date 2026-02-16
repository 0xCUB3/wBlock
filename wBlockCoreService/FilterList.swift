//
//  FilterList.swift
//  wBlock
//
//  Created by Alexander Skula on 5/25/25.
//

import Foundation

public struct FilterList: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var category: FilterListCategory
    public var isCustom: Bool = false
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
                isCustom: Bool = false,
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
        self.isCustom = isCustom
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
    
    /// Maps ISO 639-1 language codes to their primary region's flag emoji
    public static let languageToFlag: [String: String] = [
        "ar": "\u{1F1F8}\u{1F1E6}", "bg": "\u{1F1E7}\u{1F1EC}", "cs": "\u{1F1E8}\u{1F1FF}",
        "da": "\u{1F1E9}\u{1F1F0}", "de": "\u{1F1E9}\u{1F1EA}", "el": "\u{1F1EC}\u{1F1F7}",
        "es": "\u{1F1EA}\u{1F1F8}", "et": "\u{1F1EA}\u{1F1EA}", "fa": "\u{1F1EE}\u{1F1F7}",
        "fi": "\u{1F1EB}\u{1F1EE}", "fo": "\u{1F1EB}\u{1F1F4}", "fr": "\u{1F1EB}\u{1F1F7}",
        "he": "\u{1F1EE}\u{1F1F1}", "hi": "\u{1F1EE}\u{1F1F3}", "hr": "\u{1F1ED}\u{1F1F7}",
        "hu": "\u{1F1ED}\u{1F1FA}", "id": "\u{1F1EE}\u{1F1E9}", "is": "\u{1F1EE}\u{1F1F8}",
        "it": "\u{1F1EE}\u{1F1F9}", "ja": "\u{1F1EF}\u{1F1F5}", "ko": "\u{1F1F0}\u{1F1F7}",
        "lt": "\u{1F1F1}\u{1F1F9}", "lv": "\u{1F1F1}\u{1F1FB}", "mk": "\u{1F1F2}\u{1F1F0}",
        "nl": "\u{1F1F3}\u{1F1F1}", "no": "\u{1F1F3}\u{1F1F4}", "pl": "\u{1F1F5}\u{1F1F1}",
        "ps": "\u{1F1E6}\u{1F1EB}", "pt": "\u{1F1E7}\u{1F1F7}", "ro": "\u{1F1F7}\u{1F1F4}",
        "ru": "\u{1F1F7}\u{1F1FA}", "sk": "\u{1F1F8}\u{1F1F0}", "sr": "\u{1F1F7}\u{1F1F8}",
        "sv": "\u{1F1F8}\u{1F1EA}", "tg": "\u{1F1F9}\u{1F1EF}", "th": "\u{1F1F9}\u{1F1ED}",
        "tr": "\u{1F1F9}\u{1F1F7}", "uk": "\u{1F1FA}\u{1F1E6}", "vi": "\u{1F1FB}\u{1F1F3}",
        "zh": "\u{1F1E8}\u{1F1F3}",
    ]

    /// Returns flag emojis for this filter's languages, or nil if none
    public var flagEmojis: String? {
        guard !languages.isEmpty else { return nil }
        let flags = languages.compactMap { Self.languageToFlag[$0] }
        return flags.isEmpty ? nil : flags.joined(separator: " ")
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
