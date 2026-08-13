#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let manager = try source("wBlockCoreService/UserScriptManager.swift")
let view = try source("wBlock/UserScriptManagerView.swift")
let badges = try source("wBlock/InfoBadgeSupport.swift")

require(manager.contains("public func setUserScriptMetadataOverrides"), "metadata overrides need a manager API")
require(manager.contains("await persistUserScriptsNow(invalidateExecutionCache: false)"), "metadata overrides must persist before the editor closes")
require(manager.contains("let persistedName = script.name.trimmingCharacters"), "disk hydration must capture the persisted display name")
require(manager.contains("let persistedDescription = script.description"), "disk hydration must capture the persisted description")
require(manager.contains("hydratedScript.name = script.name"), "disk hydration must restore a local display name override")
require(manager.contains("hydratedScript.description = persistedDescription"), "disk hydration must restore a local description override")

require(badges.contains("enum InfoBadgeSupport"), "metadata status must use the shared badge support")
require(badges.contains("static func userScriptBadges("), "userscript badges need the current shared flow")
for required in [
    "var badges: [InfoBadgeKind] = [script.isUserStyle ? .userstyle : .userscript]",
    "if isBuiltIn",
    "else if script.isLocal",
    "if !script.version.isEmpty",
    "if !isDownloaded, !script.isLocal",
] {
    require(badges.contains(required), "badge matrix is missing current behavior: \(required)")
}
require(view.contains("ForEach(Array(InfoBadgeSupport.userScriptBadges("), "Info view must render the shared userscript badge matrix")
require(view.contains("isDownloaded: isDownloaded"), "Info view must pass download state to badge support")
require(view.contains("isBuiltIn: isBuiltIn"), "Info view must pass built-in state to badge support")
require(view.contains("Title is required."), "empty metadata names must report the existing validation error")
require(view.contains("InfoBadgeSupport.userScriptBadges"), "metadata Info must use the shared badge support")
require(badges.contains("badges.append(.notDownloaded)"), "shared badge support must expose missing remote content")
require(view.contains("Label(\"Copy URL\""), "metadata Info must expose Copy URL")
require(view.contains(".sheet(item: $selectedScript, onDismiss: {"), "metadata edits must refresh the list after dismissal")

print("PASS: issue 508 metadata persistence")
