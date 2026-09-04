#!/usr/bin/env swift
import Foundation

func require(_ c: Bool, _ m: String) { guard c else { fputs("FAIL: \(m)\n", stderr); exit(1) } }
func read(_ p: String) throws -> String { try String(contentsOfFile: p, encoding: .utf8) }

// #648 / #651: retry only the blockers that failed, and expose apply variants.
let manager = try read("wBlock/AppFilterManager.swift")
let pipeline = try read("wBlock/AppFilterManager+ApplyPipeline.swift")
let progress = try read("wBlock/ApplyChangesProgressView.swift")
let content = try read("wBlock/ContentView.swift")
let scriptsView = try read("wBlock/UserScriptManagerView.swift")

require(manager.contains("@Published var failedReloadTargets: [ContentBlockerTargetInfo] = []"), "failed targets are published")
require(manager.contains("self.failedReloadTargets = []\n            self.showingApplyProgressSheet = showProgress"), "a new apply clears the failed set")
require(pipeline.contains("self.failedReloadTargets = platformTargets.filter { failedReloadNames.contains($0.displayName) }"), "apply records the blockers that failed to reload")
let retry = pipeline.components(separatedBy: "func retryFailedReloads()")[1].components(separatedBy: "struct ReloadPhaseSummary")[0]
require(retry.contains("let targets = failedReloadTargets") && retry.contains("await reloadContentBlockers(targets)"), "retry reloads only the failed targets")
require(!retry.contains("applyChanges(") && !retry.contains("convert"), "retry must not re-run conversion")
require(retry.contains("self.failedReloadTargets = targets.filter { stillFailing.contains($0.displayName) }"), "retry keeps only the still-failing targets")
require(progress.contains("if !filterManager.failedReloadTargets.isEmpty {") && progress.contains("filterManager.retryFailedReloads()"), "summary sheet offers the retry button")
require(content.contains("Button(\"Apply Without Checking for Updates\") { filterManager.forceApplyChanges() }"), "filters tab menu offers force apply")
require(scriptsView.contains("Button(\"Apply Without Checking for Updates\", action: onForceApplyChanges)"), "userscripts tab menu offers force apply")
print("PASS test_issue_648_retry_failed_reloads")
