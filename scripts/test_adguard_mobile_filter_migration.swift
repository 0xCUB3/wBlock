import Foundation

@main
struct AdGuardMobileFilterMigrationTests {
    static func main() throws {
        let loaderSource = try read("wBlock/FilterListLoader.swift")
        let protobufSource = try read("wBlockCoreService/ProtobufDataManager+Extensions.swift")
        let appSource = try read("wBlock/wBlockApp.swift")

        let appFilterManagerSource = try read("wBlock/AppFilterManager.swift")
        expect(
            loaderSource.contains("https://filters.adtidy.org/ios/filters/11.txt"),
            "expected AdGuard Mobile Filter to use the iOS metadata endpoint"
        )
        expect(
            loaderSource.contains("\"https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_11_Mobile/filter.txt\":"),
            "expected legacy mobile filter URL to be migrated"
        )
        expect(
            occurrenceCount(of: "AdGuard URL Tracking Protection Filter", in: loaderSource) >= 3,
            "expected AdGuard URL Tracking Protection Filter to be in the default catalog"
        )
        expect(
            loaderSource.contains("https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_17_TrackParam/filter.txt"),
            "expected AdGuard URL Tracking Protection Filter to use the TrackParam endpoint"
        )
        expect(
            occurrenceCount(of: "Actually Legitimate URL Shortener Tool", in: loaderSource) >= 3,
            "expected Actually Legitimate URL Shortener Tool to be in the default catalog and recommended sets"
        )
        expect(
            loaderSource.contains("https://raw.githubusercontent.com/DandelionSprout/adfilt/master/LegitimateURLShortener.txt"),
            "expected Actually Legitimate URL Shortener Tool to use the upstream DandelionSprout endpoint"
        )
        expect(
            appFilterManagerSource.contains("filter_17_TrackParam") == false,
            "expected URL tracking protection not to be treated as deprecated"
        )
        expect(
            protobufSource.contains("func migrateLegacyFilterURLs() async"),
            "expected protobuf migration entrypoint for legacy filter URLs"
        )
        expect(
            protobufSource.contains("AdGuard Mobile Filter"),
            "expected mobile filter identification to survive URL migration"
        )
        expect(
            appSource.contains("await dataManager.migrateLegacyFilterURLs()"),
            "expected startup to persist legacy filter URL migrations"
        )

        print("ok")
    }

    private static func read(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
