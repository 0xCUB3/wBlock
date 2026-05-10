#!/usr/bin/env swift

import Foundation

let source = try String(contentsOfFile: "wBlockCoreService/UserScriptManager.swift", encoding: .utf8)
let tinyShieldURL = "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/tinyShield.user.js"

guard source.contains("name: \"tinyShield\"") else {
    fputs("FAIL: tinyShield built-in userscript definition is missing\n", stderr)
    exit(1)
}

guard source.contains(tinyShieldURL) else {
    fputs("FAIL: tinyShield should use the global upstream userscript URL, not a regional grouped URL\n", stderr)
    exit(1)
}

guard source.contains("name: \"tinyShield\",\n            url: \"\(tinyShieldURL)\",\n            isEnabledByDefault: false") else {
    fputs("FAIL: tinyShield should be available but disabled by default\n", stderr)
    exit(1)
}

print("PASS: built-in userscript definitions")
