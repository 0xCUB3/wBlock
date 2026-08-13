#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = try String(contentsOf: root.appendingPathComponent("wBlock/UserScriptManagerView.swift"), encoding: .utf8)
func check(_ condition: Bool, _ message: String) { guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) } }

let modeStart = source.range(of: "private var macosModeContent")!.lowerBound
let cardStart = source.range(of: "private var macosURLCard", range: modeStart..<source.endIndex)!.lowerBound
let mode = String(source[modeStart..<cardStart])
check(mode.components(separatedBy: "requirementsPanel").count - 1 == 1, "macOS URL mode must place requirements exactly once")
let bodyStart = source.range(of: "private var macosBody")!.lowerBound
let body = String(source[bodyStart...])
check(!body.contains("if addMode == .url {\n                        requirementsPanel"), "macOS body must not append a duplicate panel")
print("PASS")
