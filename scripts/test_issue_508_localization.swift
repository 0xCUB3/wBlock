#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let locales = ["ar", "de", "el", "en", "es", "fr", "hu", "it", "ja", "ko", "pl", "pt-BR", "ro", "ru", "tr", "zh-Hans", "zh-Hant"]
let requiredKeys = [
    "The selected file is too large. Maximum size is 10 MB.",
    "Requirements", "Disable Essential Filter?", "Replace Existing Content?",
    "Clear Element Zapper Rules?", "Clear All",
    "This recommended filter is part of wBlock’s essential protection. Disabling it may reduce blocking coverage.",
    "Pasting will replace the existing editor content.",
    "This removes all saved element zapper rules from every site.",
    "Clear Element Zapper Rules", "Advanced", "Help", "FAQ", "Report Issues",
    "Contact Us", "Version", "Developer", "GPL-3.0 License", "Privacy Policy",
    "Use a valid http:// or https:// URL", "Include a host name",
    "Do not use a userscript URL ending in .js, .mjs, or .cjs",
    "wBlock will fetch and enable the filter list automatically",
    "Starts with http:// or https://", "Ends with .js, .user.js, or .user.css",
    "Hosted on a trusted source"
]
let englishCopyAllowlist: Set<String> = ["FAQ", "GPL-3.0 License"]

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func table(for locale: String) -> [String: String] {
    let url = root.appendingPathComponent("wBlock/\(locale).lproj/Localizable.strings")
    guard let value = NSDictionary(contentsOf: url) as? [String: String] else {
        fail("could not parse \(url.path)")
    }
    return value
}

let english = table(for: "en")
var tables: [String: [String: String]] = [:]
for locale in locales {
    let values = table(for: locale)
    tables[locale] = values
    guard Set(values.keys) == Set(english.keys) else {
        fail("key parity mismatch in \(locale)")
    }
    for key in requiredKeys {
        guard let value = values[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("missing or empty \(key) in \(locale)")
        }
        if locale != "en", value == key && !englishCopyAllowlist.contains(key) {
            fail("copied English for \(key) in \(locale)")
        }
    }
}

for key in requiredKeys where key.contains("%@") {
    for locale in locales {
        guard tables[locale]![key]!.contains("%@") else {
            fail("placeholder lost for \(key) in \(locale)")
        }
    }
}
print("PASS")
