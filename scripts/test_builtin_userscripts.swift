#!/usr/bin/env swift

import Foundation

let source = try String(contentsOfFile: "wBlockCoreService/UserScriptManager.swift", encoding: .utf8)
let viewSource = try String(contentsOfFile: "wBlock/UserScriptManagerView.swift", encoding: .utf8)
let onboardingSource = try String(contentsOfFile: "wBlock/OnboardingView.swift", encoding: .utf8)
let tinyShieldURL = "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/tinyShield.user.js"
let tinyShieldDescription = "tinyShield helps block ads reinserted by Ad-Shield on matching sites."
let expectedForeignGroups: [(domain: String, languages: String)] = [
    ("autobild.de", "[\"de\"]"),
    ("bild.de", "[\"de\"]"),
    ("computerbild.de", "[\"de\"]"),
    ("gutefrage.net", "[\"de\"]"),
    ("welt.de", "[\"de\"]"),
    ("geo.fr", "[\"fr\"]"),
    ("lerobert.com", "[\"fr\"]"),
    ("programme-tv.net", "[\"fr\"]"),
    ("kuruma-news.jp", "[\"ja\"]"),
    ("oricon.co.jp", "[\"ja\"]"),
    ("toyokeizai.net", "[\"ja\"]"),
    ("dogdrip.net", "[\"ko\"]"),
    ("sportalkorea.com", "[\"ko\"]"),
    ("ygosu.com", "[\"ko\"]"),
    ("dziennik.pl", "[\"pl\"]"),
    ("doviz.com", "[\"tr\"]"),
    ("elnacional.cat", "[\"ca\"]"),
    ("pravda.com.ua", "[\"uk\"]"),
    ("slobodnadalmacija.hr", "[\"hr\"]"),
]

guard source.contains("name: \"tinyShield\"") else {
    fputs("FAIL: tinyShield built-in userscript definition is missing\n", stderr)
    exit(1)
}

guard source.contains(tinyShieldURL) else {
    fputs("FAIL: tinyShield should use the global upstream userscript URL, not a regional grouped URL\n", stderr)
    exit(1)
}

guard source.contains("name: \"tinyShield\",\n            url: tinyShieldURL,\n            isEnabledByDefault: false,\n            description: tinyShieldDescription") else {
    fputs("FAIL: tinyShield should be available but disabled by default with a usable description\n", stderr)
    exit(1)
}

for expected in expectedForeignGroups {
    let expectedDefinition = "tinyShieldGroupedDefinition(\"\(expected.domain)\", languages: \(expected.languages))"
    guard source.contains(expectedDefinition) else {
        fputs("FAIL: missing foreign tinyShield userscript/language mapping for \(expected.domain)\n", stderr)
        exit(1)
    }

    let initial = expected.domain.prefix(1).lowercased()
    let expectedURL = "dist/grouped/\(initial)/tinyShield-\(expected.domain).user.js"
    guard source.contains(expectedURL) || source.contains("tinyShieldGroupedDefinition(\"\(expected.domain)\", languages: \(expected.languages))") else {
        fputs("FAIL: \(expected.domain) should use its grouped tinyShield URL\n", stderr)
        exit(1)
    }
}

guard source.contains("section: .foreign") else {
    fputs("FAIL: foreign tinyShield definitions should be marked as foreign\n", stderr)
    exit(1)
}

guard source.contains("languagesByURL") && source.contains("builtInLanguages(for userScript: UserScript)") else {
    fputs("FAIL: built-in userscripts should expose language associations\n", stderr)
    exit(1)
}

guard source.contains("description: tinyShieldDescription") else {
    fputs("FAIL: tinyShield definitions should not fall back to the generic Default userscript description\n", stderr)
    exit(1)
}

guard source.contains("refreshDefaultUserScriptDescriptionsIfNeeded()") else {
    fputs("FAIL: existing default userscript placeholders should be refreshed\n", stderr)
    exit(1)
}

guard viewSource.contains("DisclosureGroup(isExpanded: $isForeignUserScriptsExpanded)") else {
    fputs("FAIL: userscript UI should render foreign userscripts in a collapsible section\n", stderr)
    exit(1)
}

guard viewSource.contains("scriptSection.id == .foreign") && viewSource.contains("Text(\"Foreign\")") else {
    fputs("FAIL: userscript UI should render foreign userscripts in a Foreign section\n", stderr)
    exit(1)
}

guard onboardingSource.contains("builtInSection(for: script) == .foreign")
    && onboardingSource.contains("builtInLanguages(for: script)")
    && onboardingSource.contains("selectedLanguages")
else {
    fputs("FAIL: onboarding should show foreign userscripts only for selected languages\n", stderr)
    exit(1)
}

print("PASS: built-in userscript definitions")
