#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = try String(contentsOf: root.appendingPathComponent("wBlock/SettingsView.swift"), encoding: .utf8)
func check(_ condition: Bool, _ message: String) { guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) } }

let start = source.range(of: "private var advancedSection")!
let end = source.range(of: "private var helpSection", range: start.lowerBound..<source.endIndex)!
let advanced = String(source[start.lowerBound..<end.lowerBound])
check(advanced.contains("logTimestampControls"), "Advanced must contain the log controls")
check(source.contains("Toggle(\"Sync timestamps with device timezone\""), "device time-zone toggle must label its timestamp behavior")
check(source.contains("Controls the time zone used when displaying and exporting log timestamps."), "timestamp toggle must keep its explanation")
check(!source.contains("Picker(\"Time zone\""), "timestamp settings must not show a custom time-zone picker")
check(!source.contains("Text(\"Log Timestamps\""), "timestamp settings must not repeat a large heading")
print("PASS")
