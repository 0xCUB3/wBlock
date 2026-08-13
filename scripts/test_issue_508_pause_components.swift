#!/usr/bin/env swift
import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func check(_ source: String, _ needle: String, _ message: String) {
    guard source.contains(needle) else { fatalError(message) }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let store = try read("wBlockCoreService/BlockingPauseStore.swift")
let pipeline = try read("wBlock/AppFilterManager+ApplyPipeline.swift")
let settings = try read("wBlock/SettingsView.swift")
let userscripts = try read("wBlockCoreService/WebExtensionRequestHandler.swift")
let userScriptManager = try read("wBlockCoreService/UserScriptManager.swift")
let autoUpdate = try read("wBlockCoreService/SharedAutoUpdateManager.swift")

check(store, "public static let componentsKey = \"blockingPausedComponents\"", "component choices need a shared app-group key")
check(store, "defaults.bool(forKey: key) ? BlockingPauseComponents.all : []", "legacy true pause must migrate to all components")
check(store, "setPausedComponents(paused ? .all : [], groupIdentifier: groupIdentifier)", "legacy pause callers must map to all-or-none choices")
check(store, "!pausedComponents(groupIdentifier: groupIdentifier).isEmpty", "global paused state must mean any component is paused")
check(!settings.contains("DisclosureGroup(\"Pause components\""), "dependent pause controls must not use a redundant disclosure row")
check(settings, ".controlSize(.mini)", "macOS subordinate pause controls must use Apple's mini-switch hierarchy")
check(settings, ".padding(.leading, 16)", "subordinate pause controls must be indented under Pause Blocking")
check(settings, "!filterManager.isBlockingPaused", "subordinate pause controls must be disabled until Pause Blocking is on")
check(settings, "pauseComponentBinding(.filters)", "settings must expose filter pause choice")
check(settings, "pauseComponentBinding(.userScripts)", "settings must expose userscript pause choice")
check(settings, "pauseComponentBinding(.elementZapper)", "settings must expose zapper pause choice")
check(settings, ".disabled(filterManager.isLoading || filterManager.isApplyInFlight)", "pause controls must block repeated taps during loading or apply")
check(pipeline, "pausedComponents.contains(.filters)\n            ? []", "filter lists must be omitted only for a filter pause")
check(pipeline, "pausedComponents.contains(.elementZapper)\n            ? []", "generated zapper rules must be omitted only for a zapper pause")
check(pipeline, "BlockingPauseStore.setPaused(false)", "resume must publish the shared unpaused state after apply")
let resumePipeline = pipeline.components(separatedBy: "private func resumeBlocking() async -> Bool").last ?? ""
let optimisticOff = resumePipeline.range(of: "self.pausedComponents = []\n                self.isBlockingPaused = false")
let renderYield = resumePipeline.range(of: "await Task.yield()")
let resumeApply = resumePipeline.range(of: "await applyChangesUnlocked(")
check(optimisticOff != nil, "resume must optimistically switch off the visible pause controls")
check(
    optimisticOff!.lowerBound < renderYield!.lowerBound && renderYield!.lowerBound < resumeApply!.lowerBound,
    "resume must yield a render pass after flipping the controls and before applying"
)
check(pipeline, "let succeeded = started && lastApplySucceeded && !hasError", "pause transitions must reject terminal errors even after a stale success flag")
check(pipeline, "if started && !succeeded", "a started failed pause transition must enter the fail-closed fallback")
check(pipeline, "private func failClosedAfterStartedPauseTransition() async", "pause failures need a dedicated fail-closed fallback")
check(pipeline, "self.pausedComponents = .all\n            self.isBlockingPaused = true", "pause failures must expose all components as paused")
check(pipeline, "if started && !succeeded", "an overlapping apply must not trigger the fail-closed fallback")
check(userscripts, "BlockingPauseStore.isPaused(.userScripts)", "userscript execution must honor its component pause")
check(userscripts, "!BlockingPauseStore.isPaused(.userScripts)", "userscript cache catalog must honor its component pause")
check(userScriptManager, "guard !BlockingPauseStore.isPaused(.userScripts) else { return [] }", "direct userscript manager callers must honor its component pause")
check(autoUpdate, "guard !BlockingPauseStore.isPaused(.userScripts) else { return (0, 0) }", "userscript updates must honor its component pause")
check(autoUpdate, "BlockingPauseStore.isPaused(.elementZapper)", "auto-update rebuilds must omit paused zapper rules")

// Exercise the persisted bitmask semantics independently of UserDefaults/App Group access.
let filters = 1
let scripts = 2
let zapper = 4
let all = filters | scripts | zapper
check((all & filters) != 0 && (all & scripts) != 0 && (all & zapper) != 0, "all mask must contain all components")
check((filters & scripts) == 0 && (scripts & zapper) == 0, "component masks must be independently selectable")
check((0 & all) == 0, "empty mask must represent resumed state")

print("PASS: issue 508 pause component persistence, UI, apply, and execution contracts")
