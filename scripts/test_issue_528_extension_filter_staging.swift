#!/usr/bin/env swift
import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func read(_ path: String) throws -> String { try String(contentsOfFile: path, encoding: .utf8) }

// #528: the Safari extension downloads changed filter lists while browsing
// and the app rebuilds from them. The extension must never take the run
// lease on iOS or rebuild the engine.
let manager = try read("wBlockCoreService/SharedAutoUpdateManager.swift")
let handler = try read("wBlockCoreService/WebExtensionRequestHandler.swift")
let marker = try read("wBlockCoreService/StagedFilterDownloads.swift")
let source = try read("extension-src/background.js")
let bundled = try read("wBlock Scripts (iOS)/Resources/background.js")

let staging = manager.components(separatedBy: "public func stageFilterDownloadsFromExtension")[1]
    .components(separatedBy: "// MARK: - Loading / Saving")[0]
require(staging.contains("guard Self.isAppExtensionProcess"), "staging is extension-only")
require(staging.contains("getAutoUpdateEnabled()"), "respects the auto-update switch")
require(staging.contains("BlockingPauseStore.isPaused(.filters)"), "respects the filter pause")
require(staging.contains("throttled_not_eligible"), "follows the auto-update interval")
require(staging.contains("#if !os(iOS)\n") && staging.contains("SharedAutoUpdateLease.acquire"), "lease only outside iOS")
require(!staging.contains("rebuildAndReload") && !staging.contains("reloadExistingContentBlockers"), "never rebuilds or reloads from the extension")
require(staging.contains("checkAndFetchUpdates(filters: selectedFilters)"), "reuses the conditional fetch path")
require(staging.contains("StagedFilterDownloads.save(filterIDs: [])"), "writes the marker before downloading")
require(staging.contains("setAutoUpdateForceNext(true)"), "forces the next app run")

let appRun = manager.components(separatedBy: "let updateResult = try await checkAndFetchUpdates(filters: selectedFilters)")[1]
    .components(separatedBy: "// MARK: - Extension staging")[0]
require(appRun.contains("StagedFilterDownloads.load()"), "app run reads the marker")
require(appRun.contains("if !helperStagedUpdates { StagedFilterDownloads.clear() }"), "marker cleared only after a real rebuild and reload")

require(marker.contains("staged-filter-updates.json"), "marker lives in the app group")
require(handler.contains("case \"maybeStageFilterUpdates\":"), "native action registered")
require(handler.contains("stageFilterDownloadsFromExtension(trigger: \"SafariBrowsing\")"), "handler calls the staging path")
require(source.contains("sendQueuedNativeMessage({ action: \"maybeStageFilterUpdates\" })"), "extension sends the ping")
require(source.contains("maybeRefreshUserScripts().then(maybeStageFilterUpdates);"), "filters stage after the userscript check on page completion")
require(bundled.contains("maybeStageFilterUpdates"), "minified bundle carries the action")
print("PASS test_issue_528_extension_filter_staging")
