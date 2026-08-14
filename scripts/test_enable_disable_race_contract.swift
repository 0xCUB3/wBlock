#!/usr/bin/env swift
import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let content = try read("wBlock/ContentView.swift")
let manager = try read("wBlockCoreService/UserScriptManager.swift")
let view = try read("wBlock/UserScriptManagerView.swift")
let onboarding = try read("wBlock/OnboardingView.swift")
let autoUpdate = try read("wBlockCoreService/SharedAutoUpdateManager.swift")
let filters = try read("wBlockCoreService/FilterList.swift")
let cloud = try read("wBlock/CloudSyncManager.swift")

require(content.contains("filterManager.setFilterListSelection(id: filter.id, selected: newValue)"), "filter rows must apply Toggle's explicit value")
let filterRowStart = content.range(of: "struct FilterRowView: View")!.lowerBound
let filterRow = String(content[filterRowStart...])
require(!filterRow.contains("toggleFilterListSelection(id: filter.id)"), "filter rows must not invert through a stale toggle callback")

require(manager.contains("dataManagerSyncGeneration"), "userscript hydration needs a monotonic sync generation")
require(manager.contains("guard generation == dataManagerSyncGeneration else"), "stale hydration completions must be discarded")
require(manager.contains("userScriptIntentRevisions"), "userscript enable intents need per-script revisions")
require(manager.contains("latestUserScriptIntentValues"), "completed intents must remain authoritative over stale persistence observer events")
require(manager.contains("Rewrite the live array so the older completion cannot become the disk winner"), "a stale save completion must repair persistence from live state")
require(manager.contains("batchWasSuperseded"), "a superseded onboarding batch must repair the final persisted snapshot")
require(manager.contains("Even an idempotent request invalidates an older suspended enable"), "same-state intents must cancel stale enables")
require(manager.contains("public enum UserScriptMutationOrigin"), "remote writes need a distinct mutation origin")
require(manager.contains("origin: UserScriptMutationOrigin = .local"), "explicit local toggles must use the manager intent path")
require(manager.contains("isCurrentUserScriptIntent"), "suspended downloads must re-check the latest intent")
require(manager.contains("batchRevisions"), "onboarding batches need per-script intent revisions")

require(view.contains("userScriptManager.userScript(withId: script.id)"), "rows must read current manager state by ID")
require(view.contains("userScriptManager.userScriptToggleState(for: script.id)"), "rows must expose immediate desired/in-flight state")
require(view.contains("isToggleInFlight"), "rows must suppress duplicate stale writes while a toggle is in flight")
require(view.contains("setUserScript(managedScript, isEnabled: newValue)"), "remote rows must still use the explicit enable/download path")

require(onboarding.contains("await filterManager.waitUntilReady()"), "onboarding must await filter manager readiness")
require(onboarding.contains("await userScriptManager.waitUntilReady()"), "onboarding must await userscript manager readiness")
require(onboarding.contains("let currentFilters = filterManager.filterLists"), "onboarding must snapshot the then-current filter array")
require(onboarding.contains("selectedFilterIDs"), "onboarding must apply filter choices by stable IDs")
require(onboarding.contains("guard !isApplyingSettings else { return }"), "onboarding must reject duplicate Apply tasks")
require(onboarding.contains("defer { isApplyingSettings = false }"), "onboarding apply lock must always clear")
require(onboarding.contains("await userScriptManager.setEnabledScripts(withIDs: selectedScriptIDs)"), "onboarding must persist selected scripts through the batch manager API")

require(filters.contains("public enum FilterSelectionRebaser"), "selection rebasing must be a pure helper")
require(filters.contains("latestPersisted: [FilterList]"), "selection rebase must consume latest persisted filters")
require(autoUpdate.contains("FilterSelectionRebaser.rebaseSelection"), "auto-update saves must rebase selections")
require(autoUpdate.contains("let latestPersistedFilters = await ProtobufDataManager.shared.getFilterLists()"), "auto-update must reload persisted selection immediately before save")
require(autoUpdate.contains("return rebasedFilters"), "source-count hydration must return the rebased selection")

require(cloud.contains("selectionMutationRevision"), "cloud filter apply needs a local selection revision")
require(cloud.contains("stableLocalPayloadAndMutationBaseline"), "two-way sync must pair its local payload with a stable mutation baseline")
require(cloud.contains("let localMutationBaseline = localMutationRevisionSnapshot()"), "direct remote fetch must capture local mutations before network suspension")
require(cloud.contains("localMutationBaseline: LocalMutationRevisionSnapshot"), "remote apply must receive the pre-fetch conflict baseline")
require(cloud.contains("localMutationRevisionAtStart"), "cloud userscript apply needs a local mutation revision")
require(cloud.contains("origin: .remoteSync"), "remote userscript writes must not count as local intent")
require(cloud.contains("let localMutationDuringApply"), "cloud apply must detect local mutations during the remote operation")
require(cloud.contains("if !localMutationDuringApply"), "remote hashes must not become authoritative after a local mutation")
require(cloud.contains("LocalMutationDuringApply"), "cloud apply must schedule a follow-up upload after a local mutation")

struct IntentTracker {
    private(set) var revision = 0
    private(set) var desired: Bool?

    mutating func begin(_ value: Bool) -> Int {
        revision += 1
        desired = value
        return revision
    }

    func accepts(_ token: Int) -> Bool { token == revision }
}

var tracker = IntentTracker()
let suspendedEnable = tracker.begin(true)
let sameStateDisable = tracker.begin(false)
require(!tracker.accepts(suspendedEnable), "a newer same-state intent must invalidate a suspended enable")
require(tracker.accepts(sameStateDisable), "the latest intent must remain authoritative")
require(tracker.desired == false, "latest-intent-wins must preserve the newest desired state")

print("PASS")
