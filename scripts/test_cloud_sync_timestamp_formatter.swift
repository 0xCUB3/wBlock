import Foundation

@main
struct CloudSyncTimestampFormatterTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(year: 2026, month: 3, day: 30, hour: 18, minute: 0, second: 0, calendar: calendar)

        expectEqual(
            CloudSyncTimestampFormatter.lastSyncLine(
                for: nil,
                relativeTo: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Not synced yet",
            "expected empty state copy when no sync has happened"
        )

        expectEqual(
            CloudSyncTimestampFormatter.lastSyncLine(
                for: now.addingTimeInterval(-30),
                relativeTo: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Synced just now",
            "expected near-immediate syncs to avoid countdown wording"
        )

        expectEqual(
            CloudSyncTimestampFormatter.lastSyncLine(
                for: now.addingTimeInterval(-(60 * 60)),
                relativeTo: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Synced 1 hour ago",
            "expected recent syncs to use relative time"
        )

        expectEqual(
            CloudSyncTimestampFormatter.lastSyncLine(
                for: date(year: 2026, month: 3, day: 30, hour: 11, minute: 35, second: 0, calendar: calendar),
                relativeTo: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Synced today at 11:35 AM",
            "expected older same-day syncs to use an explicit time"
        )

        expectEqual(
            CloudSyncTimestampFormatter.lastSyncLine(
                for: date(year: 2026, month: 3, day: 29, hour: 6, minute: 7, second: 0, calendar: calendar),
                relativeTo: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Synced yesterday at 6:07 AM",
            "expected yesterday syncs to use yesterday plus time"
        )

        expectEqual(
            CloudSyncTimestampFormatter.lastSyncLine(
                for: date(year: 2026, month: 3, day: 26, hour: 14, minute: 12, second: 0, calendar: calendar),
                relativeTo: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Synced 4 days ago",
            "expected recent multi-day syncs to stay relative"
        )

        expectEqual(
            CloudSyncTimestampFormatter.lastSyncLine(
                for: date(year: 2026, month: 3, day: 20, hour: 14, minute: 12, second: 0, calendar: calendar),
                relativeTo: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            ),
            "Synced Mar 20, 2026 at 2:12 PM",
            "expected older syncs to use a dated timestamp"
        )

        print("ok")
    }

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int,
        calendar: Calendar
    ) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )

        guard let date = calendar.date(from: components) else {
            fatalError("failed to create deterministic test date")
        }
        return date
    }

    private static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: String
    ) {
        let normalizedActual = normalizedString(actual)
        let normalizedExpected = normalizedString(expected)
        guard normalizedActual == normalizedExpected else {
            fputs("FAIL: \(message)\nactual: \(actual)\nexpected: \(expected)\n", stderr)
            exit(1)
        }
    }

    private static func normalizedString<T>(_ value: T) -> String {
        String(describing: value)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
