#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = try! String(
    contentsOf: root.appendingPathComponent("wBlock/ContentView.swift"),
    encoding: .utf8
)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

expect(source.contains("enum FilterListAddValidationMode"), "validation should expose explicit add modes")
expect(source.contains("struct FilterListAddValidation"), "validation should use a pure helper")
expect(source.contains("mode != .url || urlCount <= 1"), "URL custom-name validation must be URL-only")
expect(source.contains("case .paste, .file: return userListTitle"), "text and file modes must validate their editable title")
expect(source.contains("validationMode"), "validation must follow the active mode")
expect(source.contains("isCustomNameDuplicate"), "duplicate names must disable Add")

print("PASS: filter-list add validation contract")
