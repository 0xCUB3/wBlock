import Foundation

@main
struct AdGuardMobileFilterMigrationTests {
    static func main() throws {
        let loaderSource = try read("wBlock/FilterListLoader.swift")
        let protobufSource = try read("wBlockCoreService/ProtobufDataManager+Extensions.swift")
        let appSource = try read("wBlock/wBlockApp.swift")

        expect(
            loaderSource.contains("https://filters.adtidy.org/ios/filters/11.txt"),
            "expected AdGuard Mobile Filter to use the iOS metadata endpoint"
        )
        expect(
            loaderSource.contains("\"https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_11_Mobile/filter.txt\":"),
            "expected legacy mobile filter URL to be migrated"
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

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
