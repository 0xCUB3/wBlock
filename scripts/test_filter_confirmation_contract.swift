#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
func check(_ condition: Bool, _ message: String) { guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) } }

let content = try source("wBlock/ContentView.swift")
check(content.contains("setFilterListSelection(id: filter.id, selected: false)"), "essential confirmation must explicitly disable the captured filter")
check(!content.contains("if let filter = pendingEssentialFilter {\n                    filterManager.toggleFilterListSelection"), "essential confirmation must not toggle stale state")
let manager = try source("wBlock/AppFilterManager.swift")
check(manager.contains("func setFilterListSelection(id: UUID, selected: Bool)"), "manager must expose an idempotent setter")
let site = try source("wBlock/SiteSettingsView.swift")
check(site.contains(".alert(item: $pendingConfirmation)"), "site confirmations must share one item alert")
check(site.contains("pendingConfirmation = .reset(domain: site.domain)"), "reset action must remain available")
check(!site.contains("ElementZapperSettingsView"), "site settings must not own element zapper presentation")
let zapper = try source("wBlock/ElementZapperSettingsView.swift")
check(zapper.contains("private enum PendingConfirmation"), "element zapper must own its confirmation state")
check(zapper.contains("pendingConfirmation = .clearAll"), "element zapper clear-all action must remain available")
check(zapper.contains(".alert(item: $pendingConfirmation)"), "element zapper confirmation must use one item alert")
check(zapper.contains("deleteAllZapperRules(forHost: domain)"), "clear-all must delete rules for every domain")
print("PASS")
