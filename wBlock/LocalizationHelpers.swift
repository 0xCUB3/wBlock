//
//  LocalizationHelpers.swift
//  wBlock
//
//  Created by Codex on 2/13/26.
//

import Foundation
import wBlockCoreService

extension Locale {
    /// Display name for a regional language code. The Nordic list covers every
    /// Sámi language, but ICU names `se` North Sámi, so it gets the umbrella name.
    func regionalLanguageName(for code: String) -> String? {
        if code.lowercased() == "se" { return NSLocalizedString("Sámi", comment: "Language name") }
        return localizedString(forLanguageCode: code)
    }

    /// A language in its own name ("Deutsch" for de).
    static func nativeLanguageName(for code: String) -> String? {
        // ICU does not provide a native display name for Montenegrin.
        if code == "cnr" { return String(localized: "crnogorski") }
        if code == "se" { return String(localized: "sámegiella") }
        // ICU calls Indonesian "Indonesia", the name of the country.
        if code == "id" { return String(localized: "Bahasa Indonesia") }
        return Locale(identifier: code).localizedString(forLanguageCode: code)
    }

    static var appCurrent: Locale {
        guard let preferredLocalization = Bundle.main.preferredLocalizations.first else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: preferredLocalization)
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

        return Locale.appCurrent.regionalLanguageName(for: languageCode) ?? languageCode.uppercased()
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
            locale.regionalLanguageName(for: $0) ?? $0.uppercased()
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
        let nativeNames = languages.compactMap { Locale(identifier: $0).regionalLanguageName(for: $0) }
        return (languages + nativeNames + localizedLanguageNames(locale: locale)).contains {
            $0.localizedCaseInsensitiveContains(query)
        }
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
