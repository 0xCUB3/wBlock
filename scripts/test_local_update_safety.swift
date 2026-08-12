#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func read(_ path: String) -> String { try! String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let manager = read("wBlockCoreService/UserScriptManager.swift")
let updater = read("wBlock/FilterListUpdater.swift")
expect(manager.contains("staged.updateURL = nil"), "staged local metadata must discard update URL")
expect(manager.contains("staged.downloadURL = nil"), "staged local metadata must discard download URL")
expect(manager.contains("guard !candidate.isLocal"), "core auto-update must reject local scripts")
expect(manager.contains("guard !script.isLocal else { return nil }"), "URL resolution must reject local scripts")
expect(updater.contains("!$0.isLocal && $0.isDownloaded"), "scheduled checks must reject local scripts")
expect(updater.contains("guard !script.isLocal"), "manual update fetches must reject local scripts")
expect(updater.contains("!$0.isLocal && $0.updatesAutomatically"), "bulk updates must reject local scripts")
print("PASS: local update safety contract")
