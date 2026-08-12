#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
func check(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let editor = try source("scripts/codemirror-build/editor.js")
let bundle = try source("wBlock/Resources/CodeMirror/codemirror.bundle.js")
let bridge = try source("wBlock/CodeMirrorTextEditor.swift")

check(!editor.contains(".cm-panel.cm-search [name='close']"), "editor theme must not hide CodeMirror Close")
check(!bundle.contains(".cm-panel.cm-search [name='close']"), "generated bundle must not hide CodeMirror Close")
check(bridge.contains("\"close\": LocalizedStrings.text(\"close\""), "Close must use the localized phrase bridge")
check(bridge.contains("phrases: CodeMirrorResources.localizedPhrases"), "localized phrases must be passed to CodeMirror")

let localeDirectories = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("wBlock"), includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "lproj" }
check(localeDirectories.count == 17, "expected all 17 app locales")
for directory in localeDirectories {
    let strings = try String(contentsOf: directory.appendingPathComponent("Localizable.strings"), encoding: .utf8)
    check(strings.contains("\"close\" ="), "missing localized CodeMirror Close in \(directory.lastPathComponent)")
}

print("PASS")
