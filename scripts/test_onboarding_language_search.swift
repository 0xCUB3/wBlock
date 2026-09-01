#!/usr/bin/env swift

import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let source = try String(contentsOfFile: "wBlock/OnboardingView.swift", encoding: .utf8)
let pickerStart = source.range(of: "private var languagePicker: some View")!.lowerBound
let pickerEnd = source.range(of: "private var regionalStep: some View", range: pickerStart..<source.endIndex)!.lowerBound
let picker = String(source[pickerStart..<pickerEnd])
let optionStart = source.range(of: "private struct LanguageOption")!.lowerBound
let optionEnd = source.range(of: "private var displayLocale", range: optionStart..<source.endIndex)!.lowerBound
let option = String(source[optionStart..<optionEnd])

require(picker.contains("TextField(\"Search languages\", text: $languageSearchQuery)"), "language picker must contain a search field")
require(picker.contains("ForEach(matchingLanguagePickerOptions)"), "search matches must appear below the field")
require(!picker.contains("Menu {"), "language picker must not retain the Add menu")
require(!picker.contains("Text(\"Add\")") && !picker.contains("chevron.down"), "Add and chevron UI must be removed")
require(option.contains("[nativeName, name, code] + aliases"), "matching must search native name, display name, code, and aliases")
require(option.contains("localizedCaseInsensitiveContains(query)"), "matching must be case-insensitive and allow substrings")
require(option.contains("trimmingCharacters(in: .whitespacesAndNewlines)"), "matching must trim the query")
require(option.contains("guard !query.isEmpty else { return false }"), "an empty query must not match every language")
for alias in ["Deutsch", "espanol", "francais", "日本語", "中文", "portugues", "русский", "العربية"] {
    require(option.contains("\"\(alias)\""), "missing required language alias: \(alias)")
}

struct LanguageProbe {
    let code: String
    let name: String
    let nativeName: String
    let aliases: [String]

    func matches(_ rawQuery: String) -> Bool {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        return ([nativeName, name, code] + aliases).contains {
            $0.localizedCaseInsensitiveContains(query)
        }
    }
}

let languages = [
    LanguageProbe(code: "es", name: "Spanish", nativeName: "español", aliases: ["espanol"]),
    LanguageProbe(code: "de", name: "German", nativeName: "Deutsch", aliases: ["German"])
]
require(languages.filter { $0.matches("espanol") }.map(\.code) == ["es"], "espanol must match Spanish")
require(languages.filter { $0.matches("Deutsch") }.map(\.code) == ["de"], "Deutsch must match German")
require(languages.filter { $0.matches("   ") }.isEmpty, "empty query must not list all languages")

print("PASS: onboarding language search")
