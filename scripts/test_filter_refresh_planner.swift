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
        check(overdue.map { $0.id } == [existing.id, missing.id], "an overdue check must refresh every remote list")

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
