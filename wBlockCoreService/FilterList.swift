//
//  FilterList.swift
//  wBlock
//
//  Created by Alexander Skula on 5/25/25.
//

import Foundation

public enum FilterSelectionRebaser {
    /// Keeps downloaded metadata while taking live selection, update preferences,
    /// site exclusions, and explicit user name/description edits from persisted state.
    public static func rebaseSelection(
        snapshot: [FilterList],
        latestPersisted: [FilterList]
    ) -> [FilterList] {
        let latestByID = Dictionary(latestPersisted.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        var seenIDs = Set<UUID>()
        return snapshot.compactMap { filter in
            guard seenIDs.insert(filter.id).inserted else { return nil }
            guard let latest = latestByID[filter.id] else { return filter }
            var rebased = filter
            rebased.isSelected = latest.isSelected
            rebased.updatesAutomatically = latest.updatesAutomatically
            rebased.category = latest.category
            rebased.excludedSites = latest.excludedSites
            rebased.selectedSites = latest.selectedSites
            if latest.hasUserProvidedName || latest.hasUserProvidedName != filter.hasUserProvidedName {
                rebased.name = latest.name
            }
            rebased.hasUserProvidedName = latest.hasUserProvidedName
            if latest.hasUserProvidedDescription
                || latest.hasUserProvidedDescription != filter.hasUserProvidedDescription {
                rebased.description = latest.description
            }
            rebased.hasUserProvidedDescription = latest.hasUserProvidedDescription
            return rebased
        }
    }
}

public enum FilterListRemoteMetadataPolicy {
    public static func applying(
        title: String?,
        description: String?,
        version: String?,
        to filter: FilterList
    ) -> FilterList {
        var updatedFilter = filter
        if filter.isCustom, !filter.hasUserProvidedName, let title = sanitized(title) {
            updatedFilter.name = title
        }
        updatedFilter.version = version ?? "Unknown"
        // Built-in descriptions come from the localized catalog on every launch;
        // taking the file header here made them flip between the two texts.
        if filter.isCustom, !filter.hasUserProvidedDescription, let description = sanitized(description) {
            updatedFilter.description = description
        }
        return updatedFilter
    }

    private static func sanitized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct FilterList: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var url: URL
    public var category: FilterListCategory
    public var isCustom: Bool = false
    public var isSelected: Bool = false
    public var updatesAutomatically: Bool = true
    public var description: String = ""
    public var version: String = ""
    public var sourceRuleCount: Int?
    public var rawSourceRuleCount: Int?  // Pre-expansion count (NOT persisted; in-memory only)
    public var lastUpdated: Date?
    public var languages: [String] = []
    public var trustLevel: String? = nil
    public var etag: String? = nil
    public var serverLastModified: String? = nil
    public var limitExceededReason: String? = nil // Reason why filter was auto-disabled due to rule limits
    public var hasUserProvidedName: Bool = false
    public var hasUserProvidedDescription: Bool = false
    /// Hosts this list should not apply to (issue #653). Independent of Site Settings.
    public var excludedSites: [String] = []
    /// Nil applies everywhere; an empty selection applies nowhere.
    public var selectedSites: [String]?
    /// Source rule lines admitted for this list by the last confirmed apply.
    /// Nil when no compile-time provenance is available.
    public var uniqueRuleCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, url, category, isCustom, isSelected, updatesAutomatically, description,
             version, sourceRuleCount, lastUpdated, languages, trustLevel,
             etag, serverLastModified, limitExceededReason, hasUserProvidedName,
             hasUserProvidedDescription, excludedSites, selectedSites, admittedSourceRuleCount,
             uniqueRuleCount
        // uniqueRuleCount is decode-only legacy storage for pre-provenance estimates.
        // rawSourceRuleCount intentionally excluded — in-memory only, not persisted
    }

    public init(id: UUID = UUID(),
                name: String,
                url: URL,
                category: FilterListCategory,
                isCustom: Bool = false,
                isSelected: Bool = false,
                updatesAutomatically: Bool = true,
                description: String = "",
                version: String = "",
                sourceRuleCount: Int? = nil,
                rawSourceRuleCount: Int? = nil,
                lastUpdated: Date? = nil,
                languages: [String] = [],
                trustLevel: String? = nil,
                etag: String? = nil,
                serverLastModified: String? = nil,
                limitExceededReason: String? = nil,
                hasUserProvidedName: Bool = false,
                hasUserProvidedDescription: Bool = false,
                excludedSites: [String] = [],
                selectedSites: [String]? = nil,
                uniqueRuleCount: Int? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.category = category
        self.isCustom = isCustom
        self.isSelected = isSelected
        self.updatesAutomatically = updatesAutomatically
        self.description = description
        self.version = version
        self.sourceRuleCount = sourceRuleCount
        self.rawSourceRuleCount = rawSourceRuleCount
        self.lastUpdated = lastUpdated
        self.languages = languages
        self.trustLevel = trustLevel
        self.etag = etag
        self.serverLastModified = serverLastModified
        self.limitExceededReason = limitExceededReason
        self.hasUserProvidedName = hasUserProvidedName
        self.hasUserProvidedDescription = hasUserProvidedDescription
        self.excludedSites = FilterListSiteExclusion.normalizedDomains(from: excludedSites)
        self.selectedSites = selectedSites.map { FilterListSiteExclusion.normalizedDomains(from: $0) }
        self.uniqueRuleCount = uniqueRuleCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(URL.self, forKey: .url)
        category = try container.decode(FilterListCategory.self, forKey: .category)
        isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        isSelected = try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? false
        updatesAutomatically = try container.decodeIfPresent(Bool.self, forKey: .updatesAutomatically) ?? true
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
        sourceRuleCount = try container.decodeIfPresent(Int.self, forKey: .sourceRuleCount)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
        languages = try container.decodeIfPresent([String].self, forKey: .languages) ?? []
        trustLevel = try container.decodeIfPresent(String.self, forKey: .trustLevel)
        etag = try container.decodeIfPresent(String.self, forKey: .etag)
        serverLastModified = try container.decodeIfPresent(String.self, forKey: .serverLastModified)
        limitExceededReason = try container.decodeIfPresent(String.self, forKey: .limitExceededReason)
        hasUserProvidedName = try container.decodeIfPresent(Bool.self, forKey: .hasUserProvidedName) ?? false
        hasUserProvidedDescription = try container.decodeIfPresent(Bool.self, forKey: .hasUserProvidedDescription) ?? false
        excludedSites = FilterListSiteExclusion.normalizedDomains(
            from: try container.decodeIfPresent([String].self, forKey: .excludedSites) ?? []
        )
        selectedSites = try container.decodeIfPresent([String].self, forKey: .selectedSites)
            .map { FilterListSiteExclusion.normalizedDomains(from: $0) }
        uniqueRuleCount = try container.decodeIfPresent(Int.self, forKey: .admittedSourceRuleCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(category, forKey: .category)
        try container.encode(isCustom, forKey: .isCustom)
        try container.encode(isSelected, forKey: .isSelected)
        try container.encode(updatesAutomatically, forKey: .updatesAutomatically)
        try container.encode(description, forKey: .description)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(sourceRuleCount, forKey: .sourceRuleCount)
        try container.encodeIfPresent(lastUpdated, forKey: .lastUpdated)
        try container.encode(languages, forKey: .languages)
        try container.encodeIfPresent(trustLevel, forKey: .trustLevel)
        try container.encodeIfPresent(etag, forKey: .etag)
        try container.encodeIfPresent(serverLastModified, forKey: .serverLastModified)
        try container.encodeIfPresent(limitExceededReason, forKey: .limitExceededReason)
        try container.encode(hasUserProvidedName, forKey: .hasUserProvidedName)
        try container.encode(hasUserProvidedDescription, forKey: .hasUserProvidedDescription)
        try container.encode(excludedSites, forKey: .excludedSites)
        try container.encodeIfPresent(selectedSites, forKey: .selectedSites)
        try container.encodeIfPresent(uniqueRuleCount, forKey: .admittedSourceRuleCount)
    }
    
    /// Regions whose flags mark each ISO 639 language code. Flags are a visual aid;
    /// they don't claim a list covers every site in those countries.
    private static let languageRegions: [String: String] = [
        "ar": "EG SA MA DZ", "as": "IN", "bg": "BG", "bn": "BD", "bs": "BA",
        "cnr": "ME", "cs": "CZ", "da": "DK", "de": "DE CH AT", "dv": "MV",
        "el": "GR CY", "es": "ES AR", "et": "EE", "fa": "IR", "fi": "FI",
        "fr": "FR BE CA", "gu": "IN", "he": "IL", "hi": "IN", "hr": "HR",
        "hu": "HU", "id": "ID", "is": "IS", "it": "IT", "ja": "JP",
        "kn": "IN", "ko": "KR", "lt": "LT", "lv": "LV", "mai": "IN",
        "mk": "MK", "ml": "IN", "mr": "IN", "ms": "MY", "nb": "NO",
        "ne": "NP", "nl": "NL BE", "nn": "NO", "or": "IN", "pa": "IN",
        "pl": "PL", "ps": "AF", "pt": "BR PT", "ro": "RO MD", "ru": "RU",
        "si": "LK", "sk": "SK", "sl": "SI", "sq": "AL XK", "sr": "RS",
        "sv": "SE", "ta": "IN", "te": "IN", "tg": "TJ", "th": "TH",
        "tr": "TR", "uk": "UA", "vi": "VN", "zh": "CN TW HK MO",
    ]

    private static func flags(forLanguage code: String) -> [String] {
        (languageRegions[code] ?? "").split(separator: " ").map { region in
            String(String.UnicodeScalarView(region.unicodeScalars.compactMap {
                Unicode.Scalar(0x1F1A5 + $0.value)
            }))
        }
    }

    /// The first flag for a language, used where one language is shown on its own.
    public static func flag(forLanguage code: String) -> String? {
        flags(forLanguage: code).first
    }

    /// Returns flag emojis for this filter's languages, or nil if none
    public var flagEmojis: String? {
        var seen = Set<String>()
        let flags = languages.flatMap(Self.flags(forLanguage:)).filter { seen.insert($0).inserted }
        return flags.isEmpty ? nil : flags.joined(separator: " ")
    }

    /// Whether this is a built-in list pre-expanded by AdGuard's registry.
    /// These lists already have includes resolved and conditionals evaluated,
    /// so the preprocessor should be bypassed.
    public var isOptimizedBuiltin: Bool {
        !isCustom && url.path.hasSuffix("_optimized.txt")
    }

    /// Whether this is an inline user list (pasted rules stored locally).
    public var isInlineUserList: Bool {
        url.scheme?.lowercased() == "wblock" && url.host?.lowercased() == "userlist"
    }

    /// Whether this list is fetched over HTTP(S).
    public var isRemoteURL: Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    public var canUpdateAutomatically: Bool {
        isRemoteURL && updatesAutomatically
    }

    /// Counts effective (non-comment, non-header, non-empty) rules in filter content.
    public static func countRules(in content: String) -> Int {
        var count = 0
        content.enumerateLines { line, _ in
            if FilterRuleAnalysis.isRuleLine(line.trimmingCharacters(in: .whitespacesAndNewlines)) { count += 1 }
        }
        return count
    }

    // Shared formatters to avoid allocating new ones per row
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE 'at' h:mm a"
        return f
    }()
    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Returns a formatted string for the last updated date
    public var lastUpdatedFormatted: String? {
        guard let lastUpdated = lastUpdated else { return nil }
        
        let now = Date()
        let calendar = Calendar.current
        
        if calendar.isDate(lastUpdated, inSameDayAs: now) {
            return "Today at \(Self.timeFormatter.string(from: lastUpdated))"
        } else if let daysDifference = calendar.dateComponents([.day], from: lastUpdated, to: now).day, daysDifference < 7 {
            return Self.weekdayFormatter.string(from: lastUpdated)
        } else {
            return Self.dateOnlyFormatter.string(from: lastUpdated)
        }
    }
}

public enum FilterRefreshPlanner {
    /// Apply should not re-download lists that already exist when a successful
    /// check happened inside the auto-update interval or the list has opted out.
    /// Missing files still fetch regardless of the automatic update preference.
    /// `lastChecked` is the per-list time of the last successful check, so a run
    /// that partly failed resumes with only the lists that were not verified.
    public static func filtersRequiringNetworkRefresh(
        _ filters: [FilterList],
        fileExists: (FilterList) -> Bool,
        lastSuccessfulCheck: Date?,
        lastChecked: (FilterList) -> Date? = { _ in nil },
        interval: TimeInterval,
        now: Date = Date()
    ) -> [FilterList] {
        let skipExisting = lastSuccessfulCheck.map { last in
            interval > 0 && now.timeIntervalSince(last) < interval
        } ?? false

        // Lists that have never been downloaded block the user entirely, so
        // they go first; refreshes of lists that already work follow (#622).
        var missing: [FilterList] = []
        var refreshes: [FilterList] = []
        for filter in filters {
            guard filter.isRemoteURL else { continue }
            if !fileExists(filter) {
                missing.append(filter)
            } else if filter.canUpdateAutomatically && needsRefresh(filter) {
                refreshes.append(filter)
            }
        }
        return missing + refreshes

        func needsRefresh(_ filter: FilterList) -> Bool {
            if skipExisting { return false }
            if let lastUpdated = filter.lastUpdated,
               interval > 0,
               now.timeIntervalSince(lastUpdated) < interval {
                return false
            }
            if let checked = lastChecked(filter),
               interval > 0,
               now.timeIntervalSince(checked) < interval {
                return false
            }
            return true
        }
    }
}
