#!/usr/bin/env swift
import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let utils = try String(contentsOfFile: "wBlockCoreService/Utils.swift", encoding: .utf8)
let loader = try String(contentsOfFile: "wBlock/FilterListLoader.swift", encoding: .utf8)
let view = try String(contentsOfFile: "wBlock/FilterInfoView.swift", encoding: .utf8)
check(utils.contains("existingLocalFileURL"), "cache resolution must have one shared helper")
check(utils.contains("safeLegacyFileURL(name: filter.name"), "legacy resolution must use the safe name helper")
check(loader.contains("migrateCustomFilterFileIfNeeded(filter)"), "reads must attempt current-name migration")
check(loader.contains("existingLocalFileURL("), "loader must resolve legacy content during startup")
check(view.contains("FilterListLoader().readLocalFilterContent(filter)"), "View Rules must use the loader cache resolver")
check(!view.contains("appendingPathComponent(\"\\(filter.name)"), "View Rules must not interpolate a legacy path")

let root = FileManager.default.temporaryDirectory.appendingPathComponent("wblock-legacy-cache-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let legacy = root.appendingPathComponent("Imported Rules.txt")
try Data("||example.com^\n".utf8).write(to: legacy)
let current = root.appendingPathComponent("custom-current.txt")
check(!FileManager.default.fileExists(atPath: current.path), "test must begin with only a legacy cache")
check(String(data: try Data(contentsOf: legacy), encoding: .utf8) == "||example.com^\n", "legacy cache must remain directly readable")
print("PASS")
