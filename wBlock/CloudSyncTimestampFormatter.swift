import Foundation

enum CloudSyncTimestampFormatter {
    static func lastSyncLine(
        for date: Date?,
        relativeTo now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        guard let date else {
            return "Not synced yet"
        }

        let interval = now.timeIntervalSince(date)
        if abs(interval) < 60 {
            return "Synced just now"
        }

        if interval > 0, interval < 6 * 60 * 60, let relative = relativeIntervalString(from: interval, locale: locale) {
            return "Synced \(relative) ago"
        }

        if calendar.isDate(date, inSameDayAs: now) {
            return "Synced today at \(timeString(for: date, locale: locale, timeZone: timeZone))"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Synced yesterday at \(timeString(for: date, locale: locale, timeZone: timeZone))"
        }

        if interval > 0,
           let dayCount = dayDifference(from: date, to: now, calendar: calendar),
           dayCount <= 6
        {
            return "Synced \(dayCount) \(dayCount == 1 ? "day" : "days") ago"
        }

        return "Synced \(dateTimeString(for: date, locale: locale, timeZone: timeZone))"
    }

    private static func relativeIntervalString(from interval: TimeInterval, locale: Locale) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour] : [.minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.calendar?.locale = locale
        return formatter.string(from: interval)
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
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func dateTimeString(for date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
