#!/usr/bin/env swift

import Foundation

let source = try String(contentsOfFile: "wBlockCoreService/UserScriptManager.swift", encoding: .utf8)
let viewSource = try String(contentsOfFile: "wBlock/UserScriptManagerView.swift", encoding: .utf8)
let tinyShieldURL = "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/tinyShield.user.js"
let expectedForeignGroups = [
    "autobild.de",
    "bild.de",
    "computerbild.de",
    "gutefrage.net",
    "welt.de",
    "geo.fr",
    "lerobert.com",
    "programme-tv.net",
    "kuruma-news.jp",
    "oricon.co.jp",
    "toyokeizai.net",
    "dogdrip.net",
    "sportalkorea.com",
    "ygosu.com",
    "dziennik.pl",
    "doviz.com",
    "elnacional.cat",
    "pravda.com.ua",
    "slobodnadalmacija.hr",
]

guard source.contains("name: \"tinyShield\"") else {
    fputs("FAIL: tinyShield built-in userscript definition is missing\n", stderr)
    exit(1)
}

guard source.contains(tinyShieldURL) else {
    fputs("FAIL: tinyShield should use the global upstream userscript URL, not a regional grouped URL\n", stderr)
    exit(1)
}

guard source.contains("name: \"tinyShield\",\n            url: tinyShieldURL,\n            isEnabledByDefault: false") else {
    fputs("FAIL: tinyShield should be available but disabled by default\n", stderr)
    exit(1)
}

for domainGroup in expectedForeignGroups {
    let expectedDefinition = "tinyShieldGroupedDefinition(\"\(domainGroup)\")"
    guard source.contains(expectedDefinition) else {
        fputs("FAIL: missing foreign tinyShield userscript for \(domainGroup)\n", stderr)
        exit(1)
    }

    let initial = domainGroup.prefix(1).lowercased()
    let expectedURL = "dist/grouped/\(initial)/tinyShield-\(domainGroup).user.js"
    guard source.contains(expectedURL) || source.contains("tinyShieldGroupedDefinition(\"\(domainGroup)\")") else {
        fputs("FAIL: \(domainGroup) should use its grouped tinyShield URL\n", stderr)
        exit(1)
    }
}

guard source.contains("section: .foreign") else {
    fputs("FAIL: foreign tinyShield definitions should be marked as foreign\n", stderr)
    exit(1)
}

guard viewSource.contains("title: \"Foreign\"") && viewSource.contains("$0.builtInSection == .foreign") else {
    fputs("FAIL: userscript UI should render foreign userscripts in a Foreign section\n", stderr)
    exit(1)
}

print("PASS: built-in userscript definitions")
