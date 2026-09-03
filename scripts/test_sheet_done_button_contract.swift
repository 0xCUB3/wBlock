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
require(!design.contains("Button(\"Done\")"), "shared close button must be an X, not a Done label (#619)")
require(design.contains("Label(\"Close\", systemImage: \"xmark\")"), "toolbar close button must be an xmark with a Close accessibility label")
require(design.contains("Image(systemName: \"xmark\")"), "iOS 26 close button must use the bare xmark glyph")
require(design.contains("Image(systemName: \"xmark.circle.fill\")"), "pre-26 and macOS close button must use the filled xmark glyph")
require(design.contains(".accessibilityLabel(\"Close\")"), "icon-only close button must expose a Close label")
require(design.contains(".buttonStyle(.glass)"), "iOS 26 close button must be glass")
require(occurrenceCount("SheetDoneButton(action: onDismiss)", in: design) == 1, "SheetHeader must reuse the shared close button")
require(design.contains("var usesAutomaticStyle = false"), "shared button must support native toolbar styling")
require(design.contains(".keyboardShortcut(.cancelAction)"), "shared button must support the cancel shortcut")

for (name, text) in [
    ("FilterInfoView", filterInfo),
    ("FilterRulesView", filterInfo),
    ("FilterCategoryInfoView", categoryInfo),
    ("RuleCapacityPopoverView", content),
    ("UserScriptInfoView", userscripts),
    ("UserScriptSourceSheet", userscripts),
    ("CodeEditorSheet", userscripts),
    ("UserScriptCategoryInfoView", userscriptCategoryInfo)
] {
    require(text.contains("SheetDoneButton"), "\(name) must use SheetDoneButton")
    require(!text.contains("Button(\"Done\""), "\(name) must not duplicate Button(\"Done\")")
}

require(occurrenceCount("SheetDoneButton", in: filterInfo) == 2, "both filter detail popovers must use the shared button")
require(occurrenceCount("SheetDoneButton", in: categoryInfo) == 1, "category detail popover must use the shared button")
require(occurrenceCount("SheetDoneButton", in: content) == 1, "capacity popover must use the shared button")
require(occurrenceCount("SheetDoneButton", in: userscripts) == 4, "all userscript detail and editor overlays must use the shared button")
require(occurrenceCount("SheetDoneButton", in: userscriptCategoryInfo) == 1, "userscript category detail popover must use the shared button")
require(occurrenceCount("usesAutomaticStyle: true", in: userscripts) == 1, "only the iOS Info toolbar Done button may use native styling")
require(!content.contains("Image(systemName: \"xmark.circle.fill\")"), "capacity popover must not use a custom xmark close control")
require(content.contains("ViewThatFits(in: .vertical)"), "capacity sheet must only scroll when its content overflows")
require(!content.contains("ScrollView(.vertical) {"), "capacity sheet must not show an indicator detached from its 380pt column")
print("PASS")
