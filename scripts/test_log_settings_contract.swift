#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = try String(contentsOf: root.appendingPathComponent("wBlock/SettingsView.swift"), encoding: .utf8)
func check(_ condition: Bool, _ message: String) { guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) } }

let start = source.range(of: "private var advancedSection")!
let end = source.range(of: "private var helpSection", range: start.lowerBound..<source.endIndex)!
let advanced = String(source[start.lowerBound..<end.lowerBound])
check(advanced.contains("logTimestampControls"), "Advanced must contain the log controls")
check(source.contains("Toggle(\"Sync with device timezone\""), "device time-zone control must be restored")
check(source.contains("Picker(\"Time zone\""), "custom time-zone picker must be restored")
check(!advanced.contains("Section(\"Log Timestamps\""), "log controls must not create a duplicate nested section")
print("PASS")
