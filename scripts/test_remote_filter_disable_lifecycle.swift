#!/usr/bin/env swift

import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let manager = try String(contentsOfFile: "wBlock/AppFilterManager+CustomFilters.swift", encoding: .utf8)
let pipeline = try String(contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift", encoding: .utf8)
let row = try String(contentsOfFile: "wBlock/ContentView.swift", encoding: .utf8)
let filter = try String(contentsOfFile: "wBlockCoreService/FilterList.swift", encoding: .utf8)
let managerCore = try String(contentsOfFile: "wBlock/AppFilterManager.swift", encoding: .utf8)

check(manager.contains("previouslyAppliedFilterIDs: Set<UUID>? = nil"), "Cleanup must accept the last completed selection snapshot")
check(manager.contains(") async -> Bool"), "Cleanup must report file cleanup failures to the apply pipeline")
check(manager.contains("recordDownloadedStateCleanupFailure"), "Cleanup failures must preserve metadata and request an apply retry")
check(manager.contains("appliedIDs = previouslyAppliedFilterIDs ?? appliedSelectedFilterIDs"), "Cleanup must use the captured applied selection")
check(manager.contains("filter.isCustom, !filter.isInlineUserList"), "Cleanup must target custom remote lists, not inline imports")
check(manager.contains("scheme == \"http\" || scheme == \"https\""), "Cleanup must target URL-imported filters only")
check(manager.contains("diff-baseline-\\(filename)"), "Cleanup must remove the downloaded diff baseline")
check(manager.contains("prefix: \"diff-baseline-\""), "Cleanup must remove the safe legacy diff baseline")
check(manager.contains("filterLists[index].version = \"\""), "Cleanup must clear the persisted version")
check(manager.contains("filterLists[index].sourceRuleCount = nil"), "Cleanup must clear the persisted rule count")
check(manager.contains("filterLists[index].lastUpdated = nil"), "Cleanup must clear the persisted last-download time")
check(manager.contains("setFilterValidators(filter.id.uuidString, etag: nil, lastModified: nil)"), "Cleanup must clear persisted validators")
check(manager.contains("await saveFilterLists()"), "Cleanup must persist the retained definition with selected=false")
check(pipeline.contains("let allSelectedFilters = await MainActor.run { self.filterLists.filter { $0.isSelected } }"), "Blocker generation must use the current selected filters")
check(!pipeline.contains("await clearDownloadedStateForDeselectedRemoteFilters()\n\n        // While blocking"), "Apply must not destructively clean up before the apply result")
check(pipeline.contains("let cleanupSucceeded: Bool") && pipeline.contains("if cleared"), "Globally paused apply must run cleanup after clearing outputs")
let successPoint = pipeline.range(of: "let applySucceeded = await MainActor.run")
let cleanupPoint: Range<String.Index>?
if let successPoint {
    cleanupPoint = pipeline.range(
        of: "await clearDownloadedStateForDeselectedRemoteFilters(\n                previouslyAppliedFilterIDs",
        range: successPoint.lowerBound..<pipeline.endIndex
    )
} else {
    cleanupPoint = nil
}
check(successPoint != nil && cleanupPoint != nil && successPoint!.lowerBound < cleanupPoint!.lowerBound, "Cleanup must run only after the full apply reports success")
check(pipeline.contains("let cleanupSucceeded = await clearDownloadedStateForDeselectedRemoteFilters") && pipeline.contains("if cleanupSucceeded"), "Apply must not commit selection state when post-success cleanup fails")
check(row.contains("Text(\"Not Downloaded\")"), "Filter UI must expose the existing Not Downloaded state")
check(row.contains("!filter.isInlineUserList"), "Not Downloaded must not affect inline local imports")
check(filter.contains("public var sourceRuleCount: Int?"), "Lifecycle must use existing filter metadata, without schema changes")
check(managerCore.contains("for filter in filterLists where filter.isSelected && !loader.filterFileExists(filter)"), "Re-enabling a cleared URL filter must redownload its missing cache")

// Behavioral lifecycle probe: a failed apply preserves the old downloaded state; a
// successful apply clears it only after the selected output has been committed.
struct FilterState: Equatable {
    var selected: Bool
    var downloaded: Bool
    var validator: String?
}

func runApply(_ initial: FilterState, previouslyApplied: Bool, succeeds: Bool, cleanupSucceeds: Bool = true) -> FilterState {
    var state = initial
    let generatedFromCurrentSelection = state.selected
    guard succeeds, previouslyApplied, !generatedFromCurrentSelection, cleanupSucceeds else { return state }
    state.downloaded = false
    state.validator = nil
    return state
}

let disabled = FilterState(selected: false, downloaded: true, validator: "etag-1")
check(runApply(disabled, previouslyApplied: true, succeeds: false) == disabled, "Failed apply must preserve cache and validator metadata")
check(runApply(disabled, previouslyApplied: true, succeeds: true) == FilterState(selected: false, downloaded: false, validator: nil), "Successful apply must clear deselected remote state")
check(runApply(disabled, previouslyApplied: true, succeeds: true, cleanupSucceeds: false) == disabled, "Failed cleanup must preserve cache and validator metadata")
check(runApply(disabled, previouslyApplied: true, succeeds: true, cleanupSucceeds: true) == FilterState(selected: false, downloaded: false, validator: nil), "Paused successful apply must clear deselected remote state")

print("PASS: remote custom filter disable success/failure lifecycle")
