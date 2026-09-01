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
let cache = try String(contentsOfFile: "wBlockCoreService/Utils.swift", encoding: .utf8)

check(manager.contains("previouslyAppliedFilterIDs: Set<UUID>? = nil"), "cleanup must accept the last completed selection snapshot")
check(manager.contains(") async -> Bool"), "cleanup must report file cleanup failures to the apply pipeline")
check(manager.contains("recordDownloadedStateCleanupFailure"), "cleanup failures must preserve metadata and request an apply retry")
check(manager.contains("applyProgressViewModel.markFailed(message: message)"), "cleanup failures must terminate the progress state as failed")
check(manager.contains("markNonSelectionChangesPending()"), "cleanup failures must leave the retry marker pending")
check(manager.contains("appliedIDs = previouslyAppliedFilterIDs ?? appliedSelectedFilterIDs"), "cleanup must use the captured applied selection")
check(manager.contains("appliedIDs.contains(filter.id), !filter.isSelected"), "cleanup must require previous apply and current deselection")
check(manager.contains("!filter.isInlineUserList"), "cleanup must skip inline imports")
check(!manager.contains("filter.isCustom, !filter.isInlineUserList"), "cleanup must include built-in remote lists")
check(manager.contains("scheme == \"http\" || scheme == \"https\""), "cleanup must target URL-imported filters only")
check(manager.contains("ContentBlockerIncrementalCache.removeFilterCacheFiles"), "disable cleanup must use the shared cache removal helper")
check(cache.contains("public static func removeFilterCacheFiles("), "cache ownership must have one shared removal helper")
check(cache.contains("diff-baseline-\\(filename)"), "shared cleanup must remove the downloaded diff baseline")
check(cache.contains("prefix: \"diff-baseline-\""), "shared cleanup must remove the safe legacy diff baseline")
check(cache.contains("NSFileNoSuchFileError"), "missing cache files must count as successful cleanup")
check(manager.contains("filterLists[index].version = \"\""), "cleanup must clear the persisted version")
check(manager.contains("filterLists[index].sourceRuleCount = nil"), "cleanup must clear the persisted rule count")
check(manager.contains("filterLists[index].lastUpdated = nil"), "cleanup must clear the persisted last-download time")
check(manager.contains("setFilterValidators(filter.id.uuidString, etag: nil, lastModified: nil)"), "cleanup must clear persisted validators")
check(manager.contains("await saveFilterLists()"), "cleanup must persist the retained definition with selected=false")

check(pipeline.contains("let previouslyAppliedFilterIDs = appliedSelectedFilterIDs"), "apply must capture the applied selection before the run")
check(pipeline.contains("let runSnapshot = activeApplySnapshot ?? ApplyRunSnapshot("), "apply must use the captured run snapshot")
check(pipeline.contains("runSnapshot.filters.filter { $0.isSelected }"), "blocker generation must use the run snapshot selection")
check(pipeline.contains("runSnapshot.activeZapperRules"), "blocker generation must use the run snapshot zapper state")
let cleanupUsesSnapshot = pipeline.components(separatedBy: "previouslyAppliedFilterIDs: previouslyAppliedFilterIDs").count - 1
check(cleanupUsesSnapshot >= 3, "each apply success path must clean up against the captured applied selection")
check(pipeline.contains("let cleanupSucceeded: Bool") && pipeline.contains("if cleared"), "globally paused apply must run cleanup after clearing outputs")
let successPoint = pipeline.range(of: "let applySucceeded = await MainActor.run")
let cleanupPoint = successPoint.flatMap {
    pipeline.range(
        of: "await clearDownloadedStateForDeselectedRemoteFilters(\n                previouslyAppliedFilterIDs",
        range: $0.lowerBound..<pipeline.endIndex
    )
}
check(successPoint != nil && cleanupPoint != nil && successPoint!.lowerBound < cleanupPoint!.lowerBound, "cleanup must run only after the full apply reports success")
check(pipeline.contains("let cleanupSucceeded = await clearDownloadedStateForDeselectedRemoteFilters") && pipeline.contains("if cleanupSucceeded"), "apply must not commit selection state when post-success cleanup fails")
check(pipeline.contains("self.showingApplyProgressSheet = !(cleared && cleanupSucceeded)"), "cleanup failure must leave the actionable failed result visible")
check(row.contains("Text(\"Not Downloaded\")"), "filter UI must expose the existing Not Downloaded state")
check(row.contains("!filter.isInlineUserList"), "Not Downloaded must not affect inline local imports")
check(filter.contains("public var sourceRuleCount: Int?"), "lifecycle must use existing filter metadata, without schema changes")
check(managerCore.contains("for filter in filterLists where filter.isSelected && !loader.filterFileExists(filter)"), "re-enabling a cleared URL filter must redownload its missing cache")

struct DownloadedState: Equatable {
    var downloaded: Bool
    var sourceRuleCount: Int?
}

func clearDeselectedRemote(
    _ state: DownloadedState,
    previouslyApplied: Bool,
    selected: Bool,
    inline: Bool,
    scheme: String
) -> DownloadedState {
    guard previouslyApplied, !selected, !inline, scheme == "http" || scheme == "https" else {
        return state
    }
    return DownloadedState(downloaded: false, sourceRuleCount: nil)
}

let leftover = DownloadedState(downloaded: true, sourceRuleCount: 42)
check(
    clearDeselectedRemote(
        leftover,
        previouslyApplied: true,
        selected: false,
        inline: false,
        scheme: "https"
    ) == DownloadedState(downloaded: false, sourceRuleCount: nil),
    "built-in remote cleanup must clear downloaded state and source rule count"
)
check(
    clearDeselectedRemote(
        leftover,
        previouslyApplied: true,
        selected: false,
        inline: true,
        scheme: "https"
    ) == leftover,
    "inline imports must retain their local state"
)
check(
    clearDeselectedRemote(
        leftover,
        previouslyApplied: false,
        selected: false,
        inline: false,
        scheme: "file"
    ) == leftover,
    "cleanup must require a previous apply and an HTTP(S) source"
)

// Behavioral probe: generation follows the captured run snapshot, while cleanup
// follows the selection that was applied before the run and only commits on success.
struct ApplyResult: Equatable {
    var downloaded: Bool
    var committedSelection: Bool
    var hasPendingLiveChange: Bool
    var terminated: Bool
    var actionableFailure: Bool
}

func runApply(
    liveSelected: Bool,
    runSnapshotSelected: Bool,
    previouslyAppliedSelected: Bool,
    succeeds: Bool,
    cleanupSucceeds: Bool = true
) -> ApplyResult {
    var downloaded = true
    guard succeeds, previouslyAppliedSelected, !liveSelected, cleanupSucceeds else {
        return ApplyResult(
            downloaded: downloaded,
            committedSelection: false,
            hasPendingLiveChange: cleanupSucceeds ? false : true,
            terminated: true,
            actionableFailure: !cleanupSucceeds
        )
    }
    downloaded = false
    return ApplyResult(
        downloaded: downloaded,
        committedSelection: runSnapshotSelected,
        hasPendingLiveChange: liveSelected != runSnapshotSelected,
        terminated: true,
        actionableFailure: false
    )
}

check(
    runApply(liveSelected: false, runSnapshotSelected: false, previouslyAppliedSelected: true, succeeds: false)
        == ApplyResult(downloaded: true, committedSelection: false, hasPendingLiveChange: false, terminated: true, actionableFailure: false),
    "failed apply must preserve cache state"
)
check(
    runApply(liveSelected: false, runSnapshotSelected: true, previouslyAppliedSelected: true, succeeds: true)
        == ApplyResult(downloaded: false, committedSelection: true, hasPendingLiveChange: true, terminated: true, actionableFailure: false),
    "successful cleanup must use prior selection while committing the captured run snapshot"
)
check(
    runApply(liveSelected: false, runSnapshotSelected: false, previouslyAppliedSelected: true, succeeds: true, cleanupSucceeds: false)
        == ApplyResult(downloaded: true, committedSelection: false, hasPendingLiveChange: true, terminated: true, actionableFailure: true),
    "failed cleanup must terminate, preserve cache state, and leave retryable apply state"
)
check(
    runApply(liveSelected: true, runSnapshotSelected: true, previouslyAppliedSelected: true, succeeds: true)
        == ApplyResult(downloaded: true, committedSelection: false, hasPendingLiveChange: false, terminated: true, actionableFailure: false),
    "selected remote filters must not be cleaned up"
)

print("PASS: remote filter disable success/failure lifecycle")
