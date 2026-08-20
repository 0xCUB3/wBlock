import Foundation

func check(_ value: Bool, _ message: String) {
    if !value {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let loader = try! String(contentsOfFile: "wBlock/FilterListLoader.swift", encoding: .utf8)
check(
    loader.contains("raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/2_optimized.txt"),
    "base primary preserved"
)
check(
    loader.contains("raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/3_optimized.txt"),
    "tracking primary preserved"
)
check(
    loader.contains("raw.githubusercontent.com/List-KR/List-KR")
        && loader.contains("filters.adtidy.org/extension/safari/filters/227_optimized.txt"),
    "List-KR still migrates to adtidy 227"
)
check(
    !loader.contains("name: \"AdGuard Base Filter\"\n                url: URL(string: \"https://filters.adtidy.org"),
    "no primary retarget"
)

let catalog = try! Data(contentsOf: URL(fileURLWithPath: "catalog/filter-catalog.json"))
struct Catalog: Decodable {
    let schemaVersion: Int
    let lists: [[String: String]]
}
let decoded = try! JSONDecoder().decode(Catalog.self, from: catalog)
check(decoded.schemaVersion == 1 && decoded.lists.isEmpty, "catalog is an empty overlay")

let updater = try! String(contentsOfFile: "wBlock/FilterListUpdater.swift", encoding: .utf8)
check(
    updater.contains("if result.servedFallback") && updater.contains("etag: nil, lastModified: nil"),
    "fallback hasUpdate clears validators"
)
print("PASS")
