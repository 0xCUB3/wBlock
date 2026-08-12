#!/usr/bin/env swift
import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let view = try String(contentsOfFile: "wBlock/UserScriptManagerView.swift", encoding: .utf8)
check(view.contains("@State private var metadataRefreshGeneration = 0"), "metadata refreshes need a generation guard")
check(view.contains("let editorRevision = editorController.documentRevision"), "editor scans need an editor revision snapshot")
check(view.contains("let readsEditor = isShowingEditor"), "metadata source must be captured per refresh")
check(view.contains("content = await editorController.currentText()"), "CodeMirror mode must parse current editor text")
check(view.contains("content = textInput"), "simple text mode must parse current textInput")
check(view.contains("generation == metadataRefreshGeneration"), "stale metadata results must be discarded")
check(view.contains("Pasting will replace the existing content."), "paste warning must use neutral content wording")
check(view.contains("String(localized: \"On\")"), "accessibility On value must be localized")
check(view.contains("String(localized: \"Off\")"), "accessibility Off value must be localized")

let locales = ["ar", "de", "el", "en", "es", "fr", "hu", "it", "ja", "ko", "pl", "pt-BR", "ro", "ru", "tr", "zh-Hans", "zh-Hant"]
for locale in locales {
    let path = "wBlock/\(locale).lproj/Localizable.strings"
    guard let table = NSDictionary(contentsOfFile: path) as? [String: String] else { fatalError("could not parse \(path)") }
    check(table["On"]?.isEmpty == false, "On must be present in \(locale)")
    check(table["Off"]?.isEmpty == false, "Off must be present in \(locale)")
    check(table["Pasting will replace the existing content."]?.isEmpty == false, "neutral paste warning must be present in \(locale)")
}

struct RefreshProbe {
    var generation = 0
    var value = ""
    mutating func start(_ result: String) -> (Int, String) { generation += 1; return (generation, result) }
    mutating func apply(_ token: (Int, String)) { guard token.0 == generation else { return }; value = token.1 }
}
var probe = RefreshProbe()
let old = probe.start("old")
let newest = probe.start("new")
probe.apply(old)
check(probe.value.isEmpty, "an older metadata result must not overwrite newer source")
probe.apply(newest)
check(probe.value == "new", "the current metadata result must apply")
print("PASS: issue 508 text metadata source and localization")
