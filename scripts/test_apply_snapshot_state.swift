#!/usr/bin/env swift
import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

struct FilterState: Equatable {
    let id: UUID
    var name: String
    var selected: Bool
    var category: String
}

struct ApplyState {
    var live: [FilterState]
    var applied: [FilterState]

    var pending: Bool { live != applied }

    mutating func capture() -> [FilterState] { live }
    mutating func commit(_ snapshot: [FilterState]) {
        applied = snapshot
    }
}

let id = UUID()
var state = ApplyState(
    live: [FilterState(id: id, name: "Base", selected: true, category: "ads")],
    applied: [FilterState(id: id, name: "Base", selected: true, category: "ads")]
)
let snapshot = state.capture()
state.live[0].selected = false
state.commit(snapshot)
check(state.applied == snapshot, "successful apply must commit exactly its captured snapshot")
check(state.pending, "a selection mutation during apply must remain pending")

state.live[0].category = "privacy"
let resumeSnapshot = state.capture()
state.commit(resumeSnapshot)
check(state.applied == resumeSnapshot, "resume apply must capture the resumed configuration")
check(!state.pending, "resume must clear pending state only for its own snapshot")

let manager = try String(contentsOfFile: "wBlock/AppFilterManager.swift", encoding: .utf8)
let pipeline = try String(contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift", encoding: .utf8)
let updater = try String(contentsOfFile: "wBlock/FilterListUpdater.swift", encoding: .utf8)
for needle in ["captureApplySnapshot()", "commitApplySnapshot(_ snapshot: ApplyRunSnapshot)", "activeApplySnapshot", "filterConfigurations"] {
    check(manager.contains(needle), "manager is missing snapshot state: \(needle)")
}
for needle in ["let runSnapshot", "runSnapshot.filters.filter", "runSnapshot.activeZapperRules", "commitApplySnapshot(runSnapshot)"] {
    check(pipeline.contains(needle), "pipeline is missing captured-state use: \(needle)")
}
check(pipeline.contains("let refreshedSourceRuleCounts = Dictionary("), "apply must capture refreshed source counts after pre-apply hydration")
check(pipeline.contains("refreshedSourceRuleCounts[$1.id] ?? $1.sourceRuleCount ?? 0"), "source summary must prefer refreshed counts for the captured selection")
check(updater.contains("Preserve live user") && updater.contains("configuration changed while the download was in flight"), "pre-apply metadata updates must not overwrite live configuration")
print("PASS")
