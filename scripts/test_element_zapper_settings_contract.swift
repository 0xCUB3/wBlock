#!/usr/bin/env swift
import Foundation
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
func require(_ text: String, _ needle: String) { guard text.contains(needle) else { fputs("FAIL: missing \(needle)\n", stderr); exit(1) } }
let site = try source("wBlock/SiteSettingsView.swift")
let zapper = try source("wBlock/ElementZapperSettingsView.swift")
require(site, "private struct SiteSettingsSnapshot: Equatable")
require(site, "private func undoSiteMutation()")
require(site, "private func redoSiteMutation()")
guard !site.contains("ZapperRuleManager") && !site.contains("deleteZapperRule") else { fputs("FAIL: site view owns zapper state\n", stderr); exit(1) }
require(zapper, "pendingConfirmation = .clearAll")
require(zapper, "await dataManager.deleteZapperRule(rule, forHost: domain)")
require(zapper, "await dataManager.restoreZapperRule(undo.rule, forHost: undo.domain, at: undo.index)")
require(zapper, "setZapperRulesDisabled(!applied, forHost: domain)")
require(zapper, "Changes take full effect after the next apply.")
require(zapper, "Text(\"No Element Zapper Rules\")")
print("PASS")
