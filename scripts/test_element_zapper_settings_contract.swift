#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
func require(_ text: String, _ needle: String) {
    guard text.contains(needle) else {
        fputs("FAIL: missing \(needle)\n", stderr)
        exit(1)
    }
}

let site = try source("wBlock/SiteSettingsView.swift")
let zapper = try source("wBlock/ElementZapperSettingsView.swift")
let dataManager = try source("wBlockCoreService/ProtobufDataManager.swift")

require(site, "private struct SiteSettingsSnapshot: Equatable")
require(site, "private func undoSiteMutation()")
require(site, "private func redoSiteMutation()")
guard !site.contains("ZapperRuleManager") && !site.contains("deleteZapperRule") else {
    fputs("FAIL: site view owns zapper state\n", stderr)
    exit(1)
}

require(zapper, "private struct UndoEntry")
require(zapper, "originalIndex: index")
require(zapper, "insertIndex = min(max(undo.originalIndex, 0), currentRules.count)")
require(zapper, "await dataManager.deleteZapperRule(rule, forHost: domain)")
require(zapper, "await dataManager.restoreZapperRule(undo.rule, forHost: undo.domain, at: insertIndex)")
require(zapper, "await ruleManager.performMutation")
require(zapper, "filterManager.markNonSelectionChangesPending()")
require(zapper, "setZapperRulesDisabled(!enabled, forHost: domain)")
require(zapper, "pendingConfirmation = .clearAll")
require(zapper, "Element Zapper changes take full effect after the next apply.")
require(zapper, "Text(\"No Element Zapper Rules\")")
require(zapper, "Use the element zapper in the wBlock popup in Safari to hide page elements.")

require(dataManager, "public func restoreZapperRule(_ selector: String, forHost host: String, at index: Int) async")
require(dataManager, "ruleList.pendingDeletions.removeAll { $0 == selector }")
require(dataManager, "ruleList.selectors.insert(selector, at: insertIndex)")

print("PASS: element zapper settings")
