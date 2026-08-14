#!/usr/bin/env swift
import Foundation

func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
func read(_ path: String) -> String { guard let value = try? String(contentsOfFile: path, encoding: .utf8) else { fail("read \(path)") }; return value }

let manager = read("wBlockCoreService/UserScriptManager.swift")
let cloud = read("wBlock/CloudSyncRemoteUserScriptSync.swift")
let handler = read("wBlockCoreService/WebExtensionRequestHandler.swift")
let urls = [
    "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/tube-cleaner/dist/tube-cleaner.user.js",
    "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/player-cleaner/dist/player-cleaner.user.js",
    "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/dark-reader/dist/dark-reader.user.js",
]
for url in urls { guard manager.contains(url) else { fail("missing canonical URL \(url)") } }
let aliases = [
    "https://bundled.wblock.invalid/tube-cleaner.user.js": urls[0],
    "https://bundled.wblock.invalid/player-cleaner.user.js": urls[1],
    "https://bundled.wblock.invalid/dark-reader.user.js": urls[2],
]
for (legacy, canonical) in aliases {
    guard manager.contains("\"\(legacy)\": ") && cloud.contains("\"\(legacy)\": ")
        && manager.contains(canonical) && cloud.contains(canonical)
    else { fail("missing legacy alias for \(legacy)") }
}
guard manager.contains("isEnabledByDefault: false") && manager.contains("isBeta: true") && manager.contains("displayRole: .functionality") else { fail("remote defaults lost beta/functionality/default-off contract") }
guard manager.contains("legacyBundledURLsByCanonical") && manager.contains("migrateLegacyBundledUserScriptsIfNeeded") else { fail("legacy migration missing") }
guard manager.contains("updatesAutomatically = true") else { fail("legacy scripts must become auto-updating") }
guard manager.contains("mergedDisabledHosts.formUnion")
    && manager.contains("isEnabled || duplicate.isEnabled")
    && manager.contains("removeUserScriptFile(duplicate)")
else { fail("duplicate migration must preserve enablement, per-site state, and cached files") }
guard cloud.contains("legacyBundledURLs") && cloud.contains("bundled.wblock.invalid") else { fail("cloud aliases missing") }
guard handler.contains("documentStartCacheAllowed = false")
    && handler.contains("\"cacheCategory\": \"mutable\"")
    && handler.contains("allowed: false")
    && !manager.contains("enabledDocumentStartUserScriptsForCache")
else { fail("privileged bundled catalog or mutable descriptor contract missing") }
guard !manager.contains("bundledContent") && !manager.contains("BundledUserScriptSources") && !handler.contains("BundledUserScriptSources") else { fail("embedded source symbols remain") }
for path in [
    "wBlockCoreService/BundledUserscripts",
    "wBlockCoreService/BundledUserScriptSources.generated.swift",
    "wBlockCoreService/Vendored/DarkReader",
    "scripts/build_darkreader_userscript.py",
    "scripts/update_darkreader_vendor.py",
    "scripts/generate_bundled_userscripts.py",
    "tests/tube-cleaner",
] { guard !FileManager.default.fileExists(atPath: path) else { fail("embedded artifact remains: \(path)") } }
let description = "Dark Reader's MIT-licensed API engine for wBlock (beta; without the full site-fix database)."
for locale in try! FileManager.default.contentsOfDirectory(atPath: "wBlock").filter({ $0.hasSuffix(".lproj") }) {
    let strings = read("wBlock/\(locale)/Localizable.strings")
    guard strings.contains(description) else { fail("Dark Reader localization missing in \(locale)") }
    if locale != "en.lproj" {
        guard !strings.contains("\"\(description)\" = \"\(description)\";") else {
            fail("English Dark Reader description copied into \(locale)")
        }
    }
}
print("PASS: remote userscript migration contract")
