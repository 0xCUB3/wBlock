#!/usr/bin/env swift
// Source contract for the iPhone info sheets reported on Discord by cameren:
// the userscript info sheet was clipped at the medium detent, and the two
// category sheets opened as full-height sheets without a drag indicator.
import Foundation

func read(_ path: String) -> String {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("FAIL: could not read \(path)")
        exit(1)
    }
    return text
}

func require(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
        exit(1)
    }
}

let compat = read("wBlock/SwiftUICompatibility.swift")
let scripts = read("wBlock/UserScriptManagerView.swift")
let content = read("wBlock/ContentView.swift")

require(compat.contains("func tallInfoSheetPresentationCompat()"), "tall info sheet helper must exist")
require(compat.contains("presentationDetents([.fraction(0.78), .large])"), "tall info sheet must open above medium and allow large")

func sheetBody(in source: String, after marker: String) -> Substring {
    guard let start = source.range(of: marker) else {
        print("FAIL: missing \(marker)")
        exit(1)
    }
    let tail = source[start.upperBound...]
    let end = tail.range(of: "\n        }\n")?.lowerBound ?? tail.endIndex
    return tail[..<end]
}

let scriptInfo = sheetBody(in: scripts, after: "if selection.action == .info {")
require(scriptInfo.contains("UserScriptInfoView("), "userscript info sheet site must present UserScriptInfoView")
require(scriptInfo.contains(".tallInfoSheetPresentationCompat()"), "userscript info sheet must use the tall detent")

let scriptCategory = sheetBody(in: scripts, after: ".sheet(item: $selectedCategoryInfo) { category in")
require(scriptCategory.contains("UserScriptCategoryInfoView("), "userscript category sheet site must present UserScriptCategoryInfoView")
require(scriptCategory.contains(".infoSheetPresentationCompat()"), "userscript category sheet must use the info detents")

let filterCategory = sheetBody(in: content, after: ".sheet(item: $selectedCategoryInfo) { category in")
require(filterCategory.contains("FilterCategoryInfoView("), "filter category sheet site must present FilterCategoryInfoView")
require(filterCategory.contains(".infoSheetPresentationCompat()"), "filter category sheet must use the info detents")

print("PASS")
