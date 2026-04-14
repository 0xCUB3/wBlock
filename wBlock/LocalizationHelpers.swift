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
        NSLocalizedString(rawValue, comment: "Filter list category")
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
