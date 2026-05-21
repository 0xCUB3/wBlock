//
//  LocalizationHelpers.swift
//  wBlock
//
//  Created by Codex on 2/13/26.
//

import Foundation
import wBlockCoreService

extension Locale {
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

struct ForeignFilterGroup: Identifiable {
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
        var filtersByLanguage: [String: [FilterList]] = [:]

        for filter in filters {
            var languageCodes = Set(filter.languages.map { $0.lowercased() })
            if let preferred {
                languageCodes = languageCodes.intersection(preferred)
            }
            if languageCodes.isEmpty {
                languageCodes = [ungroupedLanguageCode]
            }

            for languageCode in languageCodes {
                filtersByLanguage[languageCode, default: []].append(filter)
            }
        }

        return filtersByLanguage.map { languageCode, filters in
            ForeignFilterGroup(
                languageCode: languageCode,
                title: languageTitle(for: languageCode),
                sortTitle: languageSortTitle(for: languageCode),
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

    static func recommendationBuckets(from filters: [FilterList]) -> (recommended: [FilterList], optional: [FilterList]) {
        let recommended = filters.filter { filter in
            trustRank(for: filter) < trustRank(forTrustLevel: "low") && !isSuperseded(filter)
        }
        let optional = filters.filter { filter in
            trustRank(for: filter) >= trustRank(forTrustLevel: "low") || isSuperseded(filter)
        }
        return (sortedFilters(recommended), sortedFilters(optional))
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

    private static func languageTitle(for languageCode: String) -> String {
        guard languageCode != ungroupedLanguageCode else {
            return LocalizedStrings.text("International", comment: "Filter list category")
        }

        let name = languageSortTitle(for: languageCode)
        guard let flag = FilterList.languageToFlag[languageCode], !flag.isEmpty else { return name }
        return "\(flag) \(name)"
    }

    private static func languageSortTitle(for languageCode: String) -> String {
        guard languageCode != ungroupedLanguageCode else {
            return LocalizedStrings.text("International", comment: "Filter list category")
        }

        return Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode.uppercased()
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
            NSLocalizedString("International", comment: "Filter list category")
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
