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
let manager = source("wBlockCoreService/UserScriptManager.swift")
expect(view.contains("userScriptMetaFields"), "editor mode must expose metadata override fields")
expect(view.contains("editorMetadataOverrides(for: content)"), "editor mode must autofill metadata from source")
expect(view.contains("nameOverride: metadata.name"), "editor name override must use the shared import API")
expect(view.contains("descriptionOverride: metadata.description"), "editor description override must use the shared import API")
expect(view.contains("category: selectedCategory"), "editor category override must use the shared import API")
expect(manager.contains("public func addUserScript(\n        fromSourceContent content: String"), "editor must retain the source-content import API")
expect(!view.contains("addUserScript(from: url, nameOverride:"), "URL flow must not adopt editor metadata policy")

print("PASS: issue 508 editor metadata")
