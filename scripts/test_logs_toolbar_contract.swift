#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = try String(
    contentsOf: root.appendingPathComponent("wBlock/LogsView.swift"),
    encoding: .utf8
)
func check(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let iosStart = source.range(of: ".navigationBarTitleDisplayMode(.inline)\n            .toolbar {")!.lowerBound
let macOSBranch = source.range(of: "#else", range: iosStart..<source.endIndex)!.lowerBound
let iosToolbar = String(source[iosStart..<macOSBranch])

check(iosToolbar.components(separatedBy: "ToolbarItemGroup(placement: .topBarTrailing)").count - 1 == 1 && !iosToolbar.contains("ToolbarItem(placement: .topBarTrailing)"),
      "iOS logs actions must share one trailing toolbar group")
check(!iosToolbar.contains("HStack"), "iOS logs actions must rely on native toolbar-group spacing")
check(iosToolbar.contains("Label(\"Export\", systemImage: \"square.and.arrow.up\")"),
      "iOS Export must retain its accessible label")
check(iosToolbar.contains("Label(\"Clear\", systemImage: \"trash\")"),
      "iOS Clear must retain its accessible label")
check(iosToolbar.contains(".accessibilityLabel(\"Export\")"), "iOS Export accessibility label is required")
check(iosToolbar.contains(".accessibilityLabel(\"Clear\")"), "iOS Clear accessibility label is required")
check(!iosToolbar.contains(".disabled(entries.isEmpty)"),
      "iOS Clear must not be disabled before the initial log load finishes")
check(iosToolbar.contains(".disabled(hasLoadedLogs && entries.isEmpty)"),
      "iOS Clear must disable only after logs have loaded and are empty")

let macToolbar = String(source[macOSBranch...])
check(macToolbar.contains("ToolbarItem(placement: .primaryAction)"), "macOS toolbar placement must remain unchanged")
check(macToolbar.contains("HStack"), "macOS toolbar button grouping must remain unchanged")
check(macToolbar.contains("Label(\"Export\", systemImage: \"square.and.arrow.up\")"),
      "macOS Export label must remain unchanged")
check(macToolbar.contains("Label(\"Clear\", systemImage: \"trash\")"),
      "macOS Clear label must remain unchanged")

print("PASS")
