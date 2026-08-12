#!/usr/bin/env swift

import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func check(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let manager = try read("wBlock/AppFilterManager+CustomFilters.swift")
let pipeline = try read("wBlock/AppFilterManager+ApplyPipeline.swift")
let row = try read("wBlock/ContentView.swift")
let filter = try read("wBlockCoreService/FilterList.swift")
let managerCore = try read("wBlock/AppFilterManager.swift")

check(manager.contains("clearDownloadedStateForDeselectedRemoteFilters()"), "Remote deselection cleanup must be an explicit lifecycle operation")
check(manager.contains("appliedSelectedFilterIDs.contains(filter.id)"), "Cleanup must occur when an applied selection is disabled")
check(manager.contains("filter.isCustom, !filter.isInlineUserList"), "Cleanup must target custom remote lists, not inline imports")
check(manager.contains("scheme == \"http\" || scheme == \"https\""), "Cleanup must target URL-imported filters only")
check(manager.contains("diff-baseline-\\(filename)"), "Cleanup must remove the downloaded diff baseline")
check(manager.contains("filterLists[index].version = \"\""), "Cleanup must clear the persisted version")
check(manager.contains("filterLists[index].sourceRuleCount = nil"), "Cleanup must clear the persisted rule count")
check(manager.contains("filterLists[index].lastUpdated = nil"), "Cleanup must clear the persisted last-download time")
check(manager.contains("setFilterValidators(filter.id.uuidString, etag: nil, lastModified: nil)"), "Cleanup must clear persisted validators")
check(manager.contains("await saveFilterLists()"), "Cleanup must persist the retained definition with selected=false")
check(pipeline.contains("await clearDownloadedStateForDeselectedRemoteFilters()"), "Apply must run remote cleanup before rebuilding rules")
check(row.contains("Text(\"Not Downloaded\")"), "Filter UI must expose the existing Not Downloaded state")
check(row.contains("!filter.isInlineUserList"), "Not Downloaded must not affect inline local imports")
check(filter.contains("public var sourceRuleCount: Int?"), "Lifecycle must use existing filter metadata, without schema changes")
check(managerCore.contains("for filter in filterLists where filter.isSelected && !loader.filterFileExists(filter)"), "Re-enabling a cleared URL filter must redownload its missing cache")

print("PASS: remote custom filter disable lifecycle contract")
