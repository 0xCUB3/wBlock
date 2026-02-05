//
//  UserScript.swift
//  wBlock
//
//  Created by Alexander Skula on 6/7/25.
//

import Foundation

public struct UserScriptResource: Codable, Hashable {
    public let name: String
    public let url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

public struct UserScript: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var url: URL?
    public var isEnabled: Bool = false
    public var description: String = ""
    public var version: String = ""
    public var matches: [String] = []
    public var excludeMatches: [String] = []
    public var includes: [String] = []
    public var excludes: [String] = []
    public var runAt: String = "document-end"
    public var injectInto: String = "auto"
    public var grant: [String] = []
    public var require: [String] = []
    public var resource: [UserScriptResource] = []
    public var resourceContents: [String: String] = [:] // Cached resource content
    public var noframes: Bool = false
    public var isLocal: Bool = true
    public var updateURL: String?
    public var downloadURL: String?
    public var content: String = ""
    public var lastUpdated: Date?
    
    /// Computed property to check if the userscript is downloaded and ready to use
    public var isDownloaded: Bool {
        return !content.isEmpty && content != ""
    }
    
    public init(id: UUID = UUID(), name: String, url: URL? = nil, content: String = "") {
        self.id = id
        self.name = name
        self.url = url
        self.content = content
    }
    
    /// Remove emojis from a string
    private func removeEmojis(from string: String) -> String {
        return string.unicodeScalars
            .filter { !$0.properties.isEmoji && !$0.properties.isEmojiPresentation }
            .reduce("") { $0 + String($1) }
            .trimmingCharacters(in: .whitespaces)
    }

    /// Extract metadata from userscript content
    public mutating func parseMetadata() {
        let lines = content.components(separatedBy: .newlines)
        var inMetadataBlock = false

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("// ==UserScript==") {
                inMetadataBlock = true
                continue
            }

            if trimmedLine.hasPrefix("// ==/UserScript==") {
                break
            }

            if inMetadataBlock && trimmedLine.hasPrefix("// @") {
                let components = trimmedLine.dropFirst(3).components(separatedBy: " ")
                guard components.count >= 2 else { continue }

                let key = String(components[0])
                let value = components.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)

                switch key {
                case "@name":
                    self.name = removeEmojis(from: value)
                case "@description":
                    self.description = removeEmojis(from: value)
                case "@version":
                    self.version = value
                case "@match":
                    self.matches.append(value)
                case "@exclude-match":
                    self.excludeMatches.append(value)
                case "@include":
                    self.includes.append(value)
                case "@exclude":
                    self.excludes.append(value)
                case "@run-at":
                    self.runAt = value
                case "@inject-into":
                    self.injectInto = value
                case "@grant":
                    if !self.grant.contains(value) {
                        self.grant.append(value)
                    }
                case "@require":
                    if !self.require.contains(value) {
                        self.require.append(value)
                    }
                case "@resource":
                    // Format: @resource name URL
                    let resourceComponents = value.components(separatedBy: " ")
                    if resourceComponents.count >= 2 {
                        let resourceName = resourceComponents[0]
                        let resourceURL = resourceComponents.dropFirst().joined(separator: " ")
                        self.resource.append(UserScriptResource(name: resourceName, url: resourceURL))
                    }
                case "@noframes":
                    self.noframes = true
                case "@updateURL":
                    self.updateURL = value
                case "@downloadURL":
                    self.downloadURL = value
                default:
                    break
                }
            }
        }
    }
    
    /// Check if userscript matches a given URL
    public func matches(url: String) -> Bool {
        guard URL(string: url) != nil else { return false }

        let isIncludedByMatch = matches.contains { matchesPattern(pattern: $0, url: url) }
        let isIncludedByInclude = includes.contains { matchesIncludePattern(pattern: $0, url: url) }
        let isIncluded = isIncludedByMatch || isIncludedByInclude

        guard isIncluded else { return false }

        if excludeMatches.contains(where: { matchesPattern(pattern: $0, url: url) }) {
            return false
        }

        if excludes.contains(where: { matchesIncludePattern(pattern: $0, url: url) }) {
            return false
        }

        return true
    }
    
    private func matchesPattern(pattern: String, url: String) -> Bool {
        // Handle @match patterns which follow a specific format: <scheme>://<host><path>
        // Examples: 
        // "*://*.youtube.com/*" should match "https://www.youtube.com/watch?v=..."
        // "https://example.com/*" should match "https://example.com/path"
        
        // Validate URL format
        guard URL(string: url) != nil else {
            return false
        }
        
        // Simple and robust pattern matching approach
        // Convert the userscript @match pattern to a regex pattern
        var regexPattern = NSRegularExpression.escapedPattern(for: pattern)
        
        // Now selectively unescape the wildcards we want to handle
        regexPattern = regexPattern.replacingOccurrences(of: "\\*:\\/\\/", with: "(https?|ftp)://")
        regexPattern = regexPattern.replacingOccurrences(of: "\\*\\.", with: "([^/]*\\.)?")
        regexPattern = regexPattern.replacingOccurrences(of: "\\/\\*", with: "/.*")
        regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")
        
        // Anchor the pattern to match the entire URL
        regexPattern = "^" + regexPattern + "$"
        
        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [])
            let range = NSRange(location: 0, length: url.utf16.count)
            return regex.firstMatch(in: url, options: [], range: range) != nil
        } catch {
            print("🚨 Regex compilation failed for pattern: \(pattern), regex: \(regexPattern), error: \(error)")
            return false
        }
    }
    
    private func matchesIncludePattern(pattern: String, url: String) -> Bool {
        guard URL(string: url) != nil else { return false }

        // Escape first, then restore wildcard semantics.
        var regexPattern = NSRegularExpression.escapedPattern(for: pattern)
        regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")
        regexPattern = regexPattern.replacingOccurrences(of: "\\?", with: ".")
        regexPattern = "^" + regexPattern + "$"

        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [])
            let range = NSRange(location: 0, length: url.utf16.count)
            return regex.firstMatch(in: url, options: [], range: range) != nil
        } catch {
            print("🚨 Regex compilation failed for include pattern: \(pattern), regex: \(regexPattern), error: \(error)")
            return false
        }
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
