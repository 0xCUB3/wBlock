#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func occurrenceCount(_ needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

let design = try source("wBlock/SheetDesignSystem.swift")
let filterInfo = try source("wBlock/FilterInfoView.swift")
let categoryInfo = try source("wBlock/FilterCategoryInfoView.swift")
let content = try source("wBlock/ContentView.swift")
let userscripts = try source("wBlock/UserScriptManagerView.swift")
let userscriptCategoryInfo = try source("wBlock/UserScriptCategoryInfoView.swift")

require(design.contains("struct SheetDoneButton: View"), "shared Done button must be defined")
require(design.contains("Button(\"Done\")"), "shared button must use localized Done")
require(design.contains(".glassButtonStyleCompat()"), "shared button must own glass compatibility styling")
require(design.contains("var usesAutomaticStyle = false"), "shared button must support native toolbar styling")
require(design.contains(".keyboardShortcut(.cancelAction)"), "shared button must support the cancel shortcut")

for (name, text) in [
    ("FilterInfoView", filterInfo),
    ("FilterRulesView", filterInfo),
    ("FilterCategoryInfoView", categoryInfo),
    ("RuleCapacityPopoverView", content),
    ("UserScriptInfoView", userscripts),
    ("UserScriptContentView", userscripts),
    ("UserScriptSourceSheet", userscripts),
    ("AddUserScriptEditorSheet", userscripts),
    ("UserScriptCategoryInfoView", userscriptCategoryInfo)
] {
    require(text.contains("SheetDoneButton"), "\(name) must use SheetDoneButton")
    require(!text.contains("Button(\"Done\""), "\(name) must not duplicate Button(\"Done\")")
}

require(occurrenceCount("SheetDoneButton", in: filterInfo) == 2, "both filter detail popovers must use the shared button")
require(occurrenceCount("SheetDoneButton", in: categoryInfo) == 1, "category detail popover must use the shared button")
require(occurrenceCount("SheetDoneButton", in: content) == 1, "capacity popover must use the shared button")
require(occurrenceCount("SheetDoneButton", in: userscripts) == 7, "all userscript detail and editor overlays must use the shared button")
require(occurrenceCount("SheetDoneButton", in: userscriptCategoryInfo) == 1, "userscript category detail popover must use the shared button")
require(occurrenceCount("usesAutomaticStyle: true", in: userscripts) == 3, "iOS toolbar Done buttons must use native styling exactly once")
require(!content.contains("Image(systemName: \"xmark.circle.fill\")"), "capacity popover must not use a custom xmark close control")
require(content.contains("ViewThatFits(in: .vertical)"), "capacity sheet must only scroll when its content overflows")
require(!content.contains("ScrollView(.vertical) {"), "capacity sheet must not show an indicator detached from its 380pt column")
print("PASS")
