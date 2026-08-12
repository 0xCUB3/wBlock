#!/usr/bin/env swift

import Foundation

let source = try String(contentsOfFile: "wBlock/OnboardingView.swift", encoding: .utf8)
for required in [
    "Bundle.main.preferredLocalizations.first",
    "diacriticInsensitive",
    "caseInsensitive",
    "applyingTransform(.toLatin, reverse: false)",
    "matchesLanguageSearch(option, query: query)",
] {
    guard source.contains(required) else {
        fputs("FAIL: onboarding language search is missing \(required)\n", stderr)
        exit(1)
    }
}
let folded = "Čeština".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
guard folded == "cestina" else {
    fputs("FAIL: Foundation diacritic/case folding probe failed\n", stderr)
    exit(1)
}
guard "Русский".applyingTransform(.toLatin, reverse: false) != nil else {
    fputs("FAIL: Foundation transliteration probe failed\n", stderr)
    exit(1)
}
print("PASS")
