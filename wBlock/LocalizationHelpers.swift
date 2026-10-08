//
//  LocalizationHelpers.swift
//  wBlock
//
//  Created by Codex on 2/13/26.
//

import Foundation
import wBlockCoreService

extension Locale {
    /// Native names ICU lacks or gets wrong. It has no Montenegrin, Lule, South,
    /// or Skolt Sámi name (those follow Apple's language list), and calls
    /// Indonesian "Indonesia", the name of the country.
    private static let nativeNameOverrides = [
        "cnr": "crnogorski",
        "id": "Bahasa Indonesia",
        "sma": "åarjelsaemien gïele",
        "smj": "julevsámegiella",
        "sms": "nuõrttsääʹmǩiõll",
    ]

    /// A language in its own name ("Deutsch" for de).
    static func nativeLanguageName(for code: String) -> String? {
        nativeNameOverrides[code] ?? Locale(identifier: code).localizedString(forLanguageCode: code)
    }

    static var appCurrent: Locale {
        guard let preferredLocalization = Bundle.main.preferredLocalizations.first else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: preferredLocalization)
    }
}

/// One language the regional picker can offer. Shared by onboarding and the
/// Regional category Info sheet so both pick languages the same way (#687).
struct RegionalLanguageOption: Identifiable, Hashable {
    /// Names people search by that no locale gives (#951).
    private static let synonymsByCode: [String: [String]] = [
        "bn": ["Bengali"],
        "cnr": ["црногорски"],
        "fa": ["Farsi", "Dari", "پارسی", "دری", "فارسي", "پارسي"],
        "fil": ["Tagalog"],
        "ms": ["Bahasa Malaysia"],
    ]

    /// Each language's own name in every script the system writes it in, so
    /// "srpski" finds Serbian as well as "српски" (#951).
    private static let scriptNamesByCode: [String: Set<String>] = {
        var names: [String: Set<String>] = [:]
        for identifier in Locale.availableIdentifiers {
            let locale = Locale(identifier: identifier)
            guard let code = locale.languageCode, let script = locale.scriptCode,
                  let name = Locale(identifier: "\(code)_\(script)").localizedString(forLanguageCode: code)
            else { continue }
            names[code, default: []].insert(name)
        }
        return names
    }()

    private static let english = Locale(identifier: "en")

    let code: String
    /// The name in the app's display language, used for sorting.
    let name: String
    /// The language's own name, which is what the rows show.
    let nativeName: String
    private let searchTerms: [String]

    var id: String { code }

    init(code: String, name: String? = nil, locale: Locale = displayLocale) {
        self.code = code
        self.name = name ?? locale.localizedString(forLanguageCode: code) ?? code
        let nativeName: String = Locale.nativeLanguageName(for: code) ?? self.name
        self.nativeName = nativeName
        var terms: [String] = [nativeName, self.name, code, Self.english.localizedString(forLanguageCode: code) ?? code]
        terms += Self.scriptNamesByCode[code] ?? []
        terms += Self.synonymsByCode[code] ?? []
        searchTerms = terms
    }

    /// Ignores case and accents, so "espanol" finds español (#951).
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        return searchTerms.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// The locale the app is actually displayed in, so names sort the way the
    /// user reads them rather than by the system locale.
    static var displayLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)
    }

    /// Every language that at least one regional filter list covers.
    static func fromForeignFilters(
        _ filters: [FilterList],
        locale: Locale = displayLocale
    ) -> [RegionalLanguageOption] {
        options(for: filters.filter { $0.category == .foreign }.flatMap(\.languages), locale: locale)
    }

    static func options(for codes: [String], locale: Locale) -> [RegionalLanguageOption] {
        var seen = Set<String>()
        return codes.map { $0.lowercased() }.filter { seen.insert($0).inserted }.map {
            RegionalLanguageOption(code: $0, locale: locale)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

enum LocalizedStrings {
    static func text(_ key: String, comment: String = "") -> String {
        NSLocalizedString(key, comment: comment)
    }

    static func format(_ key: String, comment: String = "", _ arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: comment), locale: .appCurrent, arguments: arguments)
    }
}

struct ForeignFilterGroup: Identifiable, Sendable {
    let languageCode: String
    let title: String
    let sortTitle: String
    let filters: [FilterList]

    var id: String { languageCode }
}

enum ForeignFilterOrganizer {
    private static let ungroupedLanguageCode = "__foreign__"

    static func groups(
        for filters: [FilterList],
        preferredLanguages: Set<String>? = nil
    ) -> [ForeignFilterGroup] {
        let preferred = preferredLanguages.map { Set($0.map { $0.lowercased() }) }
        var groups: [(languages: Set<String>, filters: [FilterList])] = []
        var seen = Set<UUID>()

        for filter in filters where seen.insert(filter.id).inserted {
            var languages = Set(filter.languages.map { $0.lowercased() })
            if let preferred {
                languages.formIntersection(preferred)
                guard !languages.isEmpty else { continue }
            }
            if languages.isEmpty { languages = [ungroupedLanguageCode] }

            // Merge overlapping coverage, including a language-specific list
            // alongside a shared list (Icelandic + Nordic, for example).
            var members = [filter]
            for index in groups.indices.reversed() where !groups[index].languages.isDisjoint(with: languages) {
                let overlapping = groups.remove(at: index)
                languages.formUnion(overlapping.languages)
                members.append(contentsOf: overlapping.filters)
            }
            groups.append((languages, members))
        }

        return groups.map { languages, filters in
            let ordered = languages.sorted {
                languageSortTitle(for: $0).localizedCaseInsensitiveCompare(languageSortTitle(for: $1)) == .orderedAscending
            }
            return ForeignFilterGroup(
                languageCode: languages.sorted().joined(separator: "+"),
                title: ordered.map { languageSortTitle(for: $0) }.joined(separator: ", "),
                sortTitle: ordered.map { languageSortTitle(for: $0) }.joined(separator: ", "),
                filters: sortedFilters(filters)
            )
        }
        .sorted { lhs, rhs in
            if lhs.languageCode == ungroupedLanguageCode { return false }
            if rhs.languageCode == ungroupedLanguageCode { return true }
            return lhs.sortTitle.localizedCaseInsensitiveCompare(rhs.sortTitle) == .orderedAscending
        }
    }

    static func sortedFilters(_ filters: [FilterList]) -> [FilterList] {
        filters.sorted { lhs, rhs in
            let lhsRank = filterPriority(lhs)
            let rhsRank = filterPriority(rhs)
            if lhsRank != rhsRank { return lhsRank < rhsRank }

            let nameComparison = lhs.localizedDisplayName.localizedCaseInsensitiveCompare(rhs.localizedDisplayName)
            if nameComparison != .orderedSame { return nameComparison == .orderedAscending }

            return lhs.url.absoluteString < rhs.url.absoluteString
        }
    }

    static func isRecommended(_ filter: FilterList) -> Bool {
        trustRank(for: filter) < trustRank(forTrustLevel: "low") && !isSuperseded(filter)
    }

    static func recommendationBuckets(from filters: [FilterList]) -> (recommended: [FilterList], optional: [FilterList]) {
        (sortedFilters(filters.filter(isRecommended)), sortedFilters(filters.filter { !isRecommended($0) }))
    }

    static func isSuperseded(_ filter: FilterList) -> Bool {
        filter.description.range(of: "Already included in", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func filterPriority(_ filter: FilterList) -> Int {
        var priority = trustRank(for: filter)
        if isSuperseded(filter) {
            priority += 10
        }
        return priority
    }

    private static func trustRank(for filter: FilterList) -> Int {
        trustRank(forTrustLevel: filter.trustLevel)
    }

    private static func trustRank(forTrustLevel trustLevel: String?) -> Int {
        switch trustLevel?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "full": return 0
        case "high": return 1
        case "medium": return 2
        case "low": return 4
        default: return 3
        }
    }

    private static func languageSortTitle(for languageCode: String) -> String {
        guard languageCode != ungroupedLanguageCode else {
            return LocalizedStrings.text("Regional", comment: "Filter list category")
        }

        return Locale.appCurrent.localizedString(forLanguageCode: languageCode) ?? languageCode.uppercased()
    }
}

enum LocalizedFormatting {
    static func percent(_ value: Double) -> String {
        value.formatted(
            .percent
                .precision(.fractionLength(0))
                .locale(.appCurrent)
        )
    }

    static func relativeDateTimeFormatter(unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .full)
        -> RelativeDateTimeFormatter
    {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .appCurrent
        formatter.unitsStyle = unitsStyle
        return formatter
    }

    static func dateComponentsFormatter(
        allowedUnits: NSCalendar.Unit,
        unitsStyle: DateComponentsFormatter.UnitsStyle,
        maximumUnitCount: Int
    ) -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = allowedUnits
        formatter.unitsStyle = unitsStyle
        formatter.maximumUnitCount = maximumUnitCount
        formatter.zeroFormattingBehavior = .dropAll

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .appCurrent
        formatter.calendar = calendar
        return formatter
    }

    static func timeFormatter(timeStyle: DateFormatter.Style = .short) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .appCurrent
        formatter.timeStyle = timeStyle
        formatter.dateStyle = .none
        return formatter
    }

    static func dateTimeFormatter(
        dateStyle: DateFormatter.Style = .medium,
        timeStyle: DateFormatter.Style = .short
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .appCurrent
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter
    }
}

extension FilterList {
    func localizedLanguageNames(locale: Locale = .appCurrent) -> [String] {
        Set(languages.map { $0.lowercased() }).map {
            locale.localizedString(forLanguageCode: $0) ?? $0.uppercased()
        }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Each language in its own name, as the language picker shows it (#940).
    /// `among` limits the list to the languages the user selected.
    func nativeLanguageNames(among selected: Set<String>? = nil) -> [String] {
        Set(languages.map { $0.lowercased() })
            .filter { selected?.contains($0) ?? true }
            .map { Locale.nativeLanguageName(for: $0) ?? $0 }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func matchesLanguage(_ query: String, locale: Locale) -> Bool {
        languages.contains { RegionalLanguageOption(code: $0.lowercased(), locale: locale).matches(query) }
    }

    var localizedDisplayName: String {
        LocalizedStrings.text(name, comment: "Filter list name")
    }

    var localizedDisplayDescription: String {
        guard !description.isEmpty else { return "" }
        return LocalizedStrings.text(description, comment: "Filter list description")
    }
}

extension UserScript {
    var localizedDisplayName: String {
        LocalizedStrings.text(name, comment: "Userscript name")
    }

    var localizedDisplayDescription: String {
        guard !description.isEmpty else { return "" }
        return LocalizedStrings.text(description, comment: "Userscript description")
    }
}

extension FilterListCategory {
    var localizedName: String {
        switch self {
        case .foreign:
            NSLocalizedString("Regional", comment: "Filter list category")
        case .custom:
            NSLocalizedString("Other", comment: "Filter list category display name")
        case .scriptExperimental:
            NSLocalizedString("Experimental", comment: "Userscript category")
        default:
            NSLocalizedString(rawValue, comment: "Filter list category")
        }
    }
}

extension LogLevel {
    var localizedName: String {
        switch self {
        case .trace:
            return NSLocalizedString("Trace", comment: "Log level")
        case .debug:
            return NSLocalizedString("Debug", comment: "Log level")
        case .info:
            return NSLocalizedString("Info", comment: "Log level")
        case .warning:
            return NSLocalizedString("Warning", comment: "Log level")
        case .error:
            return NSLocalizedString("Error", comment: "Log level")
        }
    }
}

extension LogCategory {
    var localizedName: String {
        switch self {
        case .system:
            return NSLocalizedString("System", comment: "Log category")
        case .filterUpdate:
            return NSLocalizedString("Filter Update", comment: "Log category")
        case .filterApply:
            return NSLocalizedString("Filter Apply", comment: "Log category")
        case .userScript:
            return NSLocalizedString("Userscript", comment: "Log category")
        case .network:
            return NSLocalizedString("Network", comment: "Log category")
        case .whitelist:
            return NSLocalizedString("Whitelist", comment: "Log category")
        case .autoUpdate:
            return NSLocalizedString("Auto Update", comment: "Log category")
        case .startup:
            return NSLocalizedString("Startup", comment: "Log category")
        }
    }
}
