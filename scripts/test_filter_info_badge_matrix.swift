#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) -> String {
    try! String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let support = source("wBlock/InfoBadgeSupport.swift")
let filterInfo = source("wBlock/FilterInfoView.swift")
let scriptInfo = source("wBlock/UserScriptManagerView.swift")

let filterMatrix = [
    ("inline local", "badges.append(.localImport)"),
    ("custom remote", "badges.append(.custom)"),
    ("built-in", "badges.append(.builtIn)"),
    ("enabled", "filter.isSelected ? .enabled : .disabled"),
    ("disabled uncached remote custom", "isRemote(filter.url), filter.isCustom, !filter.isSelected, filter.sourceRuleCount == nil")
]
for (name, token) in filterMatrix {
    expect(support.contains(token), "filter badge matrix is missing \(name): \(token)")
}

for token in ["script.isUserStyle ? .userstyle : .userscript", "badges.append(.builtIn)", "badges.append(.localImport)", "badges.append(.custom)", "script.isEnabled ? .enabled : .disabled", "!isDownloaded, !script.isLocal"] {
    expect(support.contains(token), "userscript badge matrix is missing \(token)")
}
expect(filterInfo.contains("InfoBadgeSupport.filterBadges(filter)"), "filter Info must consume the shared badge matrix")
expect(scriptInfo.contains("InfoBadgeSupport.userScriptBadges"), "userscript Info must consume the shared badge matrix")
expect(filterInfo.contains("Copy URL"), "filter Info must retain Copy URL")
expect(scriptInfo.contains("Copy URL"), "userscript Info must retain Copy URL")
expect(!filterInfo.contains("if filter.sourceRuleCount == nil"), "filter Info must not mark every uncached built-in as Not Downloaded")

print("PASS: filter and userscript Info badge matrix")
