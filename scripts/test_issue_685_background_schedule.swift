import Foundation

@main struct BackgroundScheduleTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let week = Int64(now.timeIntervalSince1970 + 7 * 24 * 3600)
        let scheduled = BackgroundUpdateSchedule.earliestBeginDate(now: now, intervalHours: 168, nextEligibleTime: week, lastCheckTime: 1_000_000)
        precondition(scheduled.timeIntervalSince1970 == Double(week))
        let reopened = BackgroundUpdateSchedule.earliestBeginDate(now: now.addingTimeInterval(12 * 3600), intervalHours: 168, nextEligibleTime: week, lastCheckTime: 1_000_000)
        precondition(reopened == scheduled, "app reopen must neither wake early nor postpone due date")
        let fallback = BackgroundUpdateSchedule.earliestBeginDate(now: now, intervalHours: 168, nextEligibleTime: 0, lastCheckTime: 1_000_000)
        precondition(fallback == scheduled)
        let retry = BackgroundUpdateSchedule.earliestBeginDate(now: now, intervalHours: 168, nextEligibleTime: 1_000_900, lastCheckTime: 1_000_000)
        precondition(retry.timeIntervalSince(now) == 900)
        let overdue = BackgroundUpdateSchedule.earliestBeginDate(now: now, intervalHours: 168, nextEligibleTime: 999_900, lastCheckTime: 0)
        precondition(overdue.timeIntervalSince(now) == 60)
        print("PASS #685 weekly due dates, reopen, fallback, retries and overdue backoff")
    }
}
