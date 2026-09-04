#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
func require(_ text: String, _ needle: String) {
    guard text.contains(needle) else {
        fputs("FAIL: missing \(needle)\n", stderr)
        exit(1)
    }
}

let content = try source("wBlock/ContentView.swift")
require(content, "FilterListURLSupport.normalizeURLInput(from:")
require(content, ".onChangeCompat(of: urlInput)")

let scripts = try source("wBlock/UserScriptManagerView.swift")
require(scripts, "urlInput = UserScriptURLSupport.appendingPastedURLs(string, to: urlInput)")
let urlSupport = try source("wBlockCoreService/UserScript.swift")
require(urlSupport, "let incoming = normalizePastedURL(pasted)")

let validation = try source("wBlockCoreService/FilterListValidation.swift")
require(validation, "rejoinWrappedLines")
require(validation, "looksLikePaste(from:")

print("PASS: issue 561 URL paste contract")
