#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) -> String {
    try! String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let support = source("wBlockCoreService/UserScriptDisplayCategory.swift")
let manager = source("wBlockCoreService/UserScriptManager.swift")
let view = source("wBlock/UserScriptManagerView.swift")

for category in ["Blocking", "Functionality", "Appearance", "Other"] {
    expect(support.contains("case \(category.lowercased()) ="), "missing pure display category \(category)")
    expect(support.contains("\"\(category)\""), "missing localized display label \(category)")
}
expect(support.contains("if isUserStyle { return .appearance }"), "userstyles must map to Appearance")
expect(support.contains("case .blocking:"), "blocking role must map to Blocking")
expect(support.contains("case .functionality:"), "functionality role must map to Functionality")
expect(support.contains("return .other"), "unclassified scripts must map to Other")
expect(support.contains("orderedGroups"), "display grouping must be deterministic")
expect(manager.contains("let displayRole: BuiltInUserScriptDisplayRole?"), "display role must be metadata on built-in definitions")
expect(manager.contains("displayRoleByURL"), "display role must derive from built-in identity")
expect(manager.contains("displayRole: .blocking"), "blocking built-ins must be explicitly marked")
expect(manager.contains("displayRole: .functionality"), "utility built-ins must be explicitly marked")
expect(view.contains("UserScriptDisplayCategorySupport.orderedGroups"), "view must use pure display grouping")
expect(view.contains("builtInDisplayRole: userScriptManager.builtInDisplayRole"), "view must map built-in roles")
expect(support.contains("_ = persistedCategory"), "persisted categories must remain available without creating a separate display section")
expect(view.contains("script.category"), "persisted FilterListCategory must remain in list identity")

print("PASS: userscript display category mapping and grouping")
