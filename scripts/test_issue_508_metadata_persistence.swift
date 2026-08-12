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

require(manager.contains("public func setUserScriptMetadataOverrides"), "metadata overrides need a manager API")
require(manager.contains("await persistUserScriptsNow(invalidateExecutionCache: false)"), "metadata overrides must persist before the editor closes")
require(manager.contains("let persistedName = script.name.trimmingCharacters"), "disk hydration must capture the persisted display name")
require(manager.contains("let persistedDescription = script.description"), "disk hydration must capture the persisted description")
require(manager.contains("hydratedScript.name = script.name"), "disk hydration must restore a local display name override")
require(manager.contains("hydratedScript.description = persistedDescription"), "disk hydration must restore a local description override")
require(view.contains("Title is required."), "empty metadata names must report the existing validation error")
require(view.contains("if !isDownloaded && !script.isLocal"), "metadata status must expose missing remote content")
require(view.contains("Label(\"Copy URL\""), "metadata Info must expose Copy URL")
require(view.contains(".sheet(item: $selectedScript, onDismiss: {"), "metadata edits must refresh the list after dismissal")

print("PASS: issue 508 metadata persistence")
