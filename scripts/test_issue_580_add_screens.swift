#!/usr/bin/env swift
import Foundation

func source(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}
func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func section(_ text: String, from start: String, to end: String) -> String {
    let lower = text.range(of: start)!.lowerBound
    let upper = text.range(of: end, range: lower..<text.endIndex)!.lowerBound
    return String(text[lower..<upper])
}

let scripts = try source("wBlock/UserScriptManagerView.swift")
let urlTab = section(scripts, from: "private var urlTab", to: "private var textTab")
let urlCard = section(scripts, from: "private var macosURLCard", to: "private var macosTextCard")
let textContent = section(scripts, from: "private var simpleTextContent", to: "private var macosBody")
require(!urlTab.contains("Use Editor") && !urlCard.contains("Use Editor"), "userscript URL mode must not show Use Editor")
require(textContent.contains("Label(\"Paste\"") && textContent.contains("Label(\"Use Editor\""), "userscript Text mode must show Paste and Use Editor")
require(urlTab.contains("TextField(\"Name\"") && urlTab.contains("TextField(\"Description\""), "iOS URL mode must show single-URL metadata")
require(urlCard.contains("userScriptMetaFields") && urlCard.contains("Titles will be created from each URL."), "macOS URL mode must switch between metadata and bulk guidance")
require(scripts.contains("for url in urls") && scripts.contains("addUserScript(from: url)"), "URL submit must loop the existing add pipeline")
require(scripts.contains("UserScriptURLSupport.parseRemoteURLs(from: urlInput)"), "URL mode must parse bulk input")

let filters = try source("wBlock/ContentView.swift")
let pasteTab = section(filters, from: "private var pasteTab", to: "private var fileTab")
let pasteCard = section(filters, from: "private var macosPasteCard", to: "private var macosFileCard")
require(pasteTab.contains("pasteRulesButton") && pasteCard.contains("pasteRulesButton"), "filter Text mode must show Paste on both platforms")
require(filters.contains("private func pasteRulesFromClipboard()") && filters.contains("pastedRules = string"), "filter Paste must write clipboard text into pastedRules")

print("PASS: issue 580 add-screen contract")
