//
//  UserScript.swift
//  wBlock
//
//  Created by Alexander Skula on 6/7/25.
//

import Foundation

public enum UserScriptURLSupport {
    public static func validatedRemoteURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              hasSupportedExtension(in: components.path),
              let url = components.url else {
            return nil
        }

        return url
    }

    public static func displayName(forRemoteURL url: URL) -> String {
        displayName(forFilename: url.lastPathComponent)
    }

    public static func displayName(forFilename filename: String) -> String {
        let lowercased = filename.lowercased()

        if lowercased.hasSuffix(".user.js") {
            return String(filename.dropLast(".user.js".count))
        }

        if lowercased.hasSuffix(".js") {
            return String(filename.dropLast(".js".count))
        }

        return URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
    }

    private static func hasSupportedExtension(in path: String) -> Bool {
        let lowercased = path.lowercased()
        return lowercased.hasSuffix(".user.js") || lowercased.hasSuffix(".js")
    }
}

public struct UserScriptResource: Codable, Hashable, Sendable {
    public let name: String
    public let url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

public struct UserScript: Identifiable, Codable, Hashable, Sendable {
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
    public var updatesAutomatically: Bool = true
    
    /// Computed property to check if the userscript is downloaded and ready to use
    public var isDownloaded: Bool {
        !content.isEmpty
    }

    public var executableContent: String {
        Self.executableContent(from: content)
    }

    public static func executableContent(from content: String) -> String {
        guard let metadataStart = content.range(of: "// ==UserScript==")?.lowerBound,
              let metadataEndRange = content.range(
                of: "// ==/UserScript==",
                range: metadataStart..<content.endIndex
              )
        else {
            return content
        }

        var bodyStart = metadataEndRange.upperBound
        if bodyStart < content.endIndex, content[bodyStart] == "\r" {
            bodyStart = content.index(after: bodyStart)
        }
        if bodyStart < content.endIndex, content[bodyStart] == "\n" {
            bodyStart = content.index(after: bodyStart)
        }

        if metadataStart == content.startIndex {
            return String(content[bodyStart...])
        }

        var stripped = String()
        stripped.reserveCapacity(content.count - content[metadataStart..<bodyStart].count)
        stripped.append(contentsOf: content[..<metadataStart])
        stripped.append(contentsOf: content[bodyStart...])
        return stripped
    }
    
    public init(id: UUID = UUID(), name: String, url: URL? = nil, content: String = "") {
        self.id = id
        self.name = name
        self.url = url
        self.content = content
    }

    /// Compares two dot-separated version strings numerically.
    /// Returns true only if `remote` is strictly greater than `local`.
    /// Non-numeric segment prefixes (e.g. "0b") use leading digits only; no digits = 0.
    public static func isVersionNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".", omittingEmptySubsequences: false).map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
        let localParts = local.split(separator: ".", omittingEmptySubsequences: false).map { part in
            Int(part.prefix(while: { $0.isNumber })) ?? 0
        }
        let maxLen = max(remoteParts.count, localParts.count)
        for i in 0..<maxLen {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    private static let matchRegexCache: NSCache<NSString, NSRegularExpression> = {
        let cache = NSCache<NSString, NSRegularExpression>()
        cache.countLimit = 512
        return cache
    }()

    private static let includeRegexCache: NSCache<NSString, NSRegularExpression> = {
        let cache = NSCache<NSString, NSRegularExpression>()
        cache.countLimit = 512
        return cache
    }()

    private static func cachedRegex(
        for originalPattern: String,
        cache: NSCache<NSString, NSRegularExpression>,
        buildRegexPattern: (String) -> String
    ) -> NSRegularExpression? {
        let key = originalPattern as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let regexPattern = buildRegexPattern(originalPattern)
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else {
            return nil
        }
        cache.setObject(regex, forKey: key)
        return regex
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
        // Reset metadata-backed fields so repeated parsing stays idempotent.
        description = ""
        version = ""
        matches.removeAll(keepingCapacity: true)
        excludeMatches.removeAll(keepingCapacity: true)
        includes.removeAll(keepingCapacity: true)
        excludes.removeAll(keepingCapacity: true)
        runAt = "document-end"
        injectInto = "auto"
        grant.removeAll(keepingCapacity: true)
        require.removeAll(keepingCapacity: true)
        resource.removeAll(keepingCapacity: true)
        noframes = false
        updateURL = nil
        downloadURL = nil

        // Resolve the user's preferred language code for locale-aware metadata.
        let preferredLang = Locale.current.languageCode?.lowercased() ?? "en"

        var nameByLocale: [String: String] = [:]    // locale → name
        var descByLocale: [String: String] = [:]    // locale → description
        var bareName: String?
        var bareDescription: String?

        var inMetadataBlock = false

        for line in content.split(whereSeparator: \.isNewline) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("// ==UserScript==") {
                inMetadataBlock = true
                continue
            }

            if trimmedLine.hasPrefix("// ==/UserScript==") {
                break
            }

            if inMetadataBlock && trimmedLine.hasPrefix("// @") {
                let metadataLine = trimmedLine.dropFirst(3).trimmingCharacters(in: .whitespaces)
                guard !metadataLine.isEmpty else { continue }

                let components = metadataLine.split(
                    maxSplits: 1,
                    omittingEmptySubsequences: true,
                    whereSeparator: { $0.isWhitespace }
                )
                guard let keyComponent = components.first else { continue }

                let key = String(keyComponent)
                let normalizedKey = key.lowercased()
                let directive = normalizedKey.split(
                    separator: ":",
                    maxSplits: 1,
                    omittingEmptySubsequences: true
                ).first.map(String.init) ?? normalizedKey
                // Extract locale suffix (e.g. "en" from "@name:en")
                let localeSuffix: String? = {
                    let parts = normalizedKey.split(separator: ":", maxSplits: 1)
                    return parts.count > 1 ? String(parts[1]) : nil
                }()
                let value =
                    components.count > 1
                    ? String(components[1]).trimmingCharacters(in: .whitespaces) : ""

                switch directive {
                case "@name":
                    if !value.isEmpty {
                        let cleaned = removeEmojis(from: value)
                        if let locale = localeSuffix {
                            nameByLocale[locale] = cleaned
                        } else {
                            bareName = cleaned
                        }
                    }
                case "@description":
                    let cleaned = removeEmojis(from: value)
                    if let locale = localeSuffix {
                        descByLocale[locale] = cleaned
                    } else {
                        bareDescription = cleaned
                    }
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
                    self.updateURL = value.isEmpty ? nil : value
                case "@downloadURL":
                    self.downloadURL = value.isEmpty ? nil : value
                default:
                    break
                }
            }
        }

        // Resolve locale-aware @name: prefer user locale, then "en", then bare.
        self.name = nameByLocale[preferredLang]
            ?? nameByLocale["en"]
            ?? bareName
            ?? self.name

        // Resolve locale-aware @description: prefer user locale, then "en", then bare.
        self.description = descByLocale[preferredLang]
            ?? descByLocale["en"]
            ?? bareDescription
            ?? self.description
    }
    
    /// Check if userscript matches a given URL
    public func matches(url: String) -> Bool {
        guard let parsedURL = Self.parsedMatchURL(from: url) else { return false }
        let urlRange = NSRange(location: 0, length: url.utf16.count)

        let isIncludedByMatch = matches.contains {
            matchesPattern(pattern: $0, url: url, parsedURL: parsedURL, urlRange: urlRange)
        }
        let isIncludedByInclude = includes.contains {
            matchesIncludePattern(pattern: $0, url: url, urlRange: urlRange)
        }
        let isIncluded = isIncludedByMatch || isIncludedByInclude

        guard isIncluded else { return false }

        if excludeMatches.contains(where: {
            matchesPattern(pattern: $0, url: url, parsedURL: parsedURL, urlRange: urlRange)
        }) {
            return false
        }

        if excludes.contains(where: { matchesIncludePattern(pattern: $0, url: url, urlRange: urlRange) }) {
            return false
        }

        return true
    }

    private struct ParsedMatchURL {
        let scheme: String
        let host: String
        let hostWithPort: String
        let pathAndSuffix: String
    }

    private static func parsedMatchURL(from url: String) -> ParsedMatchURL? {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased()
        else {
            return nil
        }

        let hostWithPort: String
        if let port = components.port {
            hostWithPort = "\(host):\(port)"
        } else {
            hostWithPort = host
        }

        var pathAndSuffix = components.percentEncodedPath
        if pathAndSuffix.isEmpty {
            pathAndSuffix = "/"
        }
        if let query = components.percentEncodedQuery {
            pathAndSuffix += "?\(query)"
        }
        if let fragment = components.percentEncodedFragment {
            pathAndSuffix += "#\(fragment)"
        }

        return ParsedMatchURL(
            scheme: scheme,
            host: host,
            hostWithPort: hostWithPort,
            pathAndSuffix: pathAndSuffix
        )
    }

    private func matchesPattern(
        pattern: String,
        url: String,
        parsedURL: ParsedMatchURL,
        urlRange: NSRange
    ) -> Bool {
        // Fast path for normal @match patterns. Large userscripts such as tinyShield
        // carry tens of thousands of matches, and compiling regexes for each candidate
        // adds enough document-start latency to lose races against page scripts.
        if let result = Self.matchesStructuredPattern(pattern: pattern, parsedURL: parsedURL) {
            return result
        }

        guard let regex = Self.cachedRegex(
            for: pattern,
            cache: Self.matchRegexCache,
            buildRegexPattern: { sourcePattern in
                var regexPattern = NSRegularExpression.escapedPattern(for: sourcePattern)
                regexPattern = regexPattern.replacingOccurrences(of: "\\*:\\/\\/", with: "(https?|ftp)://")
                regexPattern = regexPattern.replacingOccurrences(of: "\\*\\.", with: "([^/]*\\.)?")
                regexPattern = regexPattern.replacingOccurrences(of: "\\/\\*", with: "/.*")
                regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")
                return "^\(regexPattern)$"
            }
        ) else {
            return false
        }
        return regex.firstMatch(in: url, options: [], range: urlRange) != nil
    }

    private static func matchesStructuredPattern(pattern: String, parsedURL: ParsedMatchURL) -> Bool? {
        guard let schemeSeparator = pattern.range(of: "://") else { return nil }
        let schemePattern = pattern[..<schemeSeparator.lowerBound].lowercased()
        let remainder = pattern[schemeSeparator.upperBound...]
        guard let pathStart = remainder.firstIndex(of: "/") else { return nil }

        let hostPattern = String(remainder[..<pathStart]).lowercased()
        let pathPattern = remainder[pathStart...]

        switch schemePattern {
        case "*":
            guard parsedURL.scheme == "http" || parsedURL.scheme == "https" || parsedURL.scheme == "ftp" else {
                return false
            }
        case parsedURL.scheme:
            break
        default:
            return false
        }

        let hostValue = hostPattern.contains(":") ? parsedURL.hostWithPort : parsedURL.host
        guard matchesHostPattern(hostPattern, host: hostValue) else { return false }
        return wildcardMatch(pattern: pathPattern, value: parsedURL.pathAndSuffix)
    }

    private static func matchesHostPattern(_ pattern: String, host: String) -> Bool {
        if pattern == "*" {
            return true
        }

        if pattern.hasPrefix("*.") {
            let base = pattern.dropFirst(2)
            return host == base || host.hasSuffix(".\(base)")
        }

        return wildcardMatch(pattern: pattern[...], value: host)
    }

    private static func wildcardMatch(pattern: Substring, value: String) -> Bool {
        if pattern == "*" {
            return true
        }

        if pattern == "/*" {
            return value.hasPrefix("/")
        }

        guard pattern.contains("*") else {
            return value == pattern
        }

        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false)
        var searchStart = value.startIndex

        if let first = parts.first, !first.isEmpty {
            guard value[searchStart...].hasPrefix(first) else { return false }
            searchStart = value.index(searchStart, offsetBy: first.count)
        }

        for part in parts.dropFirst().dropLast() where !part.isEmpty {
            guard let range = value[searchStart...].range(of: part) else { return false }
            searchStart = range.upperBound
        }

        if let last = parts.last, !last.isEmpty {
            if pattern.last == "*" {
                return value[searchStart...].range(of: last) != nil
            }
            return value[searchStart...].hasSuffix(last)
        }

        return pattern.last == "*" || searchStart == value.endIndex
    }
    
    private func matchesIncludePattern(pattern: String, url: String, urlRange: NSRange) -> Bool {
        guard let regex = Self.cachedRegex(
            for: pattern,
            cache: Self.includeRegexCache,
            buildRegexPattern: { sourcePattern in
                // Escape first, then restore wildcard semantics.
                var regexPattern = NSRegularExpression.escapedPattern(for: sourcePattern)
                regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")
                regexPattern = regexPattern.replacingOccurrences(of: "\\?", with: ".")
                return "^\(regexPattern)$"
            }
        ) else {
            return false
        }
        return regex.firstMatch(in: url, options: [], range: urlRange) != nil
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
