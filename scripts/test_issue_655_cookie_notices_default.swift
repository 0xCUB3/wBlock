#!/usr/bin/env swift

import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

// #655: AdGuard Cookie Notices is on by default after onboarding on every
// platform, but disabling it must not trigger the essential-protection warning.
let loader = try String(contentsOfFile: "wBlock/FilterListLoader.swift", encoding: .utf8)
let contentView = try String(contentsOfFile: "wBlock/ContentView.swift", encoding: .utf8)

let recommendedBlocks = loader.components(separatedBy: "static let recommendedFilterNames: Set<String> = [")
expect(recommendedBlocks.count == 3, "expected macOS and iOS recommended sets")
for block in recommendedBlocks.dropFirst() {
    let body = block.components(separatedBy: "]").first ?? ""
    expect(body.contains("\"AdGuard Cookie Notices\""), "Cookie Notices missing from a recommended set")
}

expect(
    loader.contains("name: \"AdGuard Cookie Notices\",\n                url: URL(\n                    string:\n                        \"https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/18_optimized.txt\"\n                )!, category: FilterListCategory.annoyances, isSelected: true,"),
    "Cookie Notices default list entry must be selected"
)
expect(
    loader.contains("essentialFilterNames: Set<String> = recommendedFilterNames.subtracting([\"AdGuard Cookie Notices\"])"),
    "Cookie Notices must be excluded from the essential-filter set"
)
expect(
    contentView.contains("FilterListLoader.essentialFilterNames.contains(filter.name)"),
    "disable warning must key off essentialFilterNames"
)
expect(
    !contentView.contains("FilterListLoader.recommendedFilterNames.contains(filter.name)"),
    "disable warning must not use recommendedFilterNames"
)
print("PASS test_issue_655_cookie_notices_default")
