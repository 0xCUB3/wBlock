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
check(site.contains("pendingConfirmation = .clearAll"), "clear-all action must remain available")
check(site.contains("pendingConfirmation = .reset(domain: site.domain)"), "reset action must remain available")
print("PASS")
