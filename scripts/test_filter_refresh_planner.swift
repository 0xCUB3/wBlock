import Foundation
import wBlockCoreService

@main
struct FilterRefreshPlannerTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = now.addingTimeInterval(-30 * 60)
        let stale = now.addingTimeInterval(-7 * 3600)
        let existing = list("https://example.com/ads.txt")
        let missing = list("https://example.com/privacy.txt")
        let local = list("wblock://userlist/custom")
        let freshlyDownloaded = list("https://example.com/fresh.txt", lastUpdated: recent)
        let exists: (FilterList) -> Bool = { $0.id == existing.id || $0.id == freshlyDownloaded.id }

        let skipped = FilterRefreshPlanner.filtersRequiringNetworkRefresh(
            [existing, missing, local],
            fileExists: exists,
            lastSuccessfulCheck: recent,
            interval: 6 * 3600,
            now: now
        )
        check(skipped.map { $0.id } == [missing.id], "a recent check must only fetch missing remote lists")

        let overdue = FilterRefreshPlanner.filtersRequiringNetworkRefresh(
            [existing, missing, local],
            fileExists: exists,
            lastSuccessfulCheck: stale,
            interval: 6 * 3600,
            now: now
        )
        check(overdue.map { $0.id } == [missing.id, existing.id], "an overdue check must refresh every remote list, never-downloaded lists first (#622)")

        let never = FilterRefreshPlanner.filtersRequiringNetworkRefresh(
            [existing, local],
            fileExists: exists,
            lastSuccessfulCheck: nil,
            interval: 6 * 3600,
            now: now
        )
        check(never.map { $0.id } == [existing.id], "a first run must still refresh cached remote lists")

        let recentDownload = FilterRefreshPlanner.filtersRequiringNetworkRefresh(
            [freshlyDownloaded, missing],
            fileExists: exists,
            lastSuccessfulCheck: nil,
            interval: 6 * 3600,
            now: now
        )
        check(recentDownload.map { $0.id } == [missing.id], "a just-downloaded list must not be fetched again")

        // A run that verified some lists and then failed must resume with only
        // the unverified ones, even though the global check never succeeded.
        let verified = list("https://example.com/verified.txt")
        let unverified = list("https://example.com/unverified.txt")
        let bothExist: (FilterList) -> Bool = { $0.id == verified.id || $0.id == unverified.id }
        let resumed = FilterRefreshPlanner.filtersRequiringNetworkRefresh(
            [verified, unverified, missing],
            fileExists: bothExist,
            lastSuccessfulCheck: stale,
            lastChecked: { $0.id == verified.id ? recent : nil },
            interval: 6 * 3600,
            now: now
        )
        check(resumed.map { $0.id } == [missing.id, unverified.id], "a partly failed run must resume from the unverified lists, missing ones first")

        let expired = FilterRefreshPlanner.filtersRequiringNetworkRefresh(
            [verified],
            fileExists: bothExist,
            lastSuccessfulCheck: nil,
            lastChecked: { _ in stale },
            interval: 6 * 3600,
            now: now
        )
        check(expired.map { $0.id } == [verified.id], "a per-list check older than the interval must refresh again")

        let updater = try! String(
            contentsOf: URL(fileURLWithPath: "wBlock/FilterListUpdater.swift"),
            encoding: .utf8
        )
        check(!updater.contains("compareRemoteToLocal"), "update checks must not fall back to a second full download")
        check(
            updater.contains("timeoutIntervalForResource = 30"),
            "a hung host must not sit on a two-minute resource timeout"
        )
        check(
            updater.contains("FilterRefreshPlanner.filtersRequiringNetworkRefresh"),
            "apply refresh must use the freshness planner"
        )
        check(
            updater.contains("if checkedAllExisting && allSucceeded"),
            "a failed or unavailable fetch must not mark the interval as successful"
        )
        check(
            updater.contains("lastChecked: { lastCheckedByID[$0.id] }"),
            "apply refresh must feed per-list check times into the planner"
        )
        check(
            updater.contains("ProtobufDataManager.shared.setFilterLastChecked(verifiedTimes)"),
            "verified lists must persist their check time even when other lists fail"
        )
        print("PASS")
    }

    private static func list(_ url: String, lastUpdated: Date? = nil) -> FilterList {
        FilterList(
            name: url,
            url: URL(string: url)!,
            category: .ads,
            lastUpdated: lastUpdated
        )
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
