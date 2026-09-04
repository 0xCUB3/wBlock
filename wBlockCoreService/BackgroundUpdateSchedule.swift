import Foundation

public enum BackgroundUpdateSchedule {
    public static func earliestBeginDate(
        now: Date,
        intervalHours: Double,
        nextEligibleTime: Int64,
        lastCheckTime: Int64
    ) -> Date {
        let due: Date
        if nextEligibleTime > 0 {
            due = Date(timeIntervalSince1970: TimeInterval(nextEligibleTime))
        } else if lastCheckTime > 0 {
            let hours = intervalHours.isFinite && intervalHours > 0 ? intervalHours : 6
            due = Date(timeIntervalSince1970: TimeInterval(lastCheckTime) + hours * 3600)
        } else {
            due = now
        }
        // Backoff prevents immediate resubmission loops for an overdue task.
        return max(due, now.addingTimeInterval(60))
    }
}
