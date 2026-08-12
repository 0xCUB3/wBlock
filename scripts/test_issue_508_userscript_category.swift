#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) -> String {
    try! String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let view = source("wBlock/UserScriptManagerView.swift")
let model = source("wBlockCoreService/UserScript.swift")
let persistence = source("wBlockCoreService/ProtobufDataManager+Extensions.swift")

expect(view.contains("let category: FilterListCategory"), "list identity must include userscript category")
expect(view.contains("let displayCategory: UserScriptDisplayCategory"), "list identity must include display category")
expect(view.contains("UserScriptDisplayCategorySupport.category"), "userstyles and built-in roles must map deterministically")
expect(view.contains("let nonRegionalScripts = displayed.filter"), "local and remote scripts must remain visible in display groups")
expect(view.contains("FilterListCategory.userScriptCategories"), "userscript picker must use sensible categories")
expect(view.contains(".onReceive(userScriptManager.$userScripts)"), "category changes must refresh the displayed list")
expect(model.contains("public var category: FilterListCategory = .scripts"), "userscript category must have a stable model field")
expect(persistence.contains("script.category = protoData.category"), "userscript category must round-trip from protobuf")
expect(view.contains("Badge(text: \"Custom\""), "Custom badge must remain an origin badge")

print("PASS: issue 508 userscript categories")
