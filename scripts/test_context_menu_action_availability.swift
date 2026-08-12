#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let helper = try source("wBlock/ContextMenuActionAvailability.swift")
let filters = try source("wBlock/ContentView.swift")
let scripts = try source("wBlock/UserScriptManagerView.swift")
require(helper.contains("return [.info, .viewRules]"), "default filters must offer Info and View Rules")
require(helper.contains("return [.info, .editRules, .deleteList]"), "local custom filters must offer edit and delete")
require(helper.contains("return [.info, .viewRules, .deleteList]"), "remote custom filters must remain view-only")
require(helper.contains("return [.info, .viewContent]"), "default scripts must offer Info and View Content")
require(helper.contains("return [.info, .editContent, .deleteScript]"), "local custom scripts must offer edit and delete")
require(helper.contains("return [.info, .viewContent, .deleteScript]"), "remote custom scripts must not offer edit")
require(filters.contains("ContextMenuActionAvailability.filterActions(for: filter)"), "filter rows must use pure action availability")
require(scripts.contains("ContextMenuActionAvailability.userScriptActions"), "script rows must use pure action availability")
require(scripts.contains("setUserScriptMetadataOverrides"), "editable script metadata must use persisted overrides")
require(scripts.contains("canEdit: script.isLocal && !userScriptManager.isDefaultUserScript(script)"), "remote and built-in scripts must not expose edit")
print("PASS")
