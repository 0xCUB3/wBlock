import Foundation

enum CloudSyncTimestampFormatter {
    static func lastSyncLine(
        for date: Date?,
        relativeTo now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .appCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let date else {
            return String(localized: "Not synced yet")
        }

        let interval = now.timeIntervalSince(date)
        if abs(interval) < 60 {
            return String(localized: "Synced just now")
        }

        if interval > 0,
           interval < 6 * 60 * 60,
           let relative = relativeString(for: date, relativeTo: now, locale: locale)
        {
            return String.localizedStringWithFormat(
                NSLocalizedString("Synced %@", comment: "Cloud sync status"),
                relative
            )
        }

        if calendar.isDate(date, inSameDayAs: now) {
            return String.localizedStringWithFormat(
                NSLocalizedString("Synced today at %@", comment: "Cloud sync status"),
                timeString(for: date, locale: locale, timeZone: timeZone)
            )
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return String.localizedStringWithFormat(
                NSLocalizedString("Synced yesterday at %@", comment: "Cloud sync status"),
                timeString(for: date, locale: locale, timeZone: timeZone)
            )
        }

        if interval > 0,
           let days = dayDifference(from: date, to: now, calendar: calendar),
           days <= 6,
           let relative = relativeString(for: date, relativeTo: now, locale: locale)
        {
            return String.localizedStringWithFormat(
                NSLocalizedString("Synced %@", comment: "Cloud sync status"),
                relative
            )
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("Synced %@", comment: "Cloud sync status"),
            dateTimeString(for: date, locale: locale, timeZone: timeZone)
        )
    }

    private static func relativeString(for date: Date, relativeTo now: Date, locale: Locale) -> String? {
        let formatter = LocalizedFormatting.relativeDateTimeFormatter(unitsStyle: .full)
        formatter.locale = locale
        return formatter.localizedString(for: date, relativeTo: now)
    }

    private static func dayDifference(from date: Date, to now: Date, calendar: Calendar) -> Int? {
        let startOfDate = calendar.startOfDay(for: date)
        let startOfNow = calendar.startOfDay(for: now)
        guard let days = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day else {
            return nil
        }
        return days > 0 ? days : nil
    }

    private static func timeString(for date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = LocalizedFormatting.timeFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func dateTimeString(for date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = LocalizedFormatting.dateTimeFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}
