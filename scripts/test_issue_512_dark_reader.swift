#!/usr/bin/env swift
import Foundation

func fail(_ message: String) -> Never { fputs("FAIL: \(message)\n", stderr); exit(1) }
func read(_ path: String) -> String { guard let value = try? String(contentsOfFile: path, encoding: .utf8) else { fail("read \(path)") }; return value }

let manager = read("wBlockCoreService/UserScriptManager.swift")
let cloud = read("wBlock/CloudSyncRemoteUserScriptSync.swift")
let handler = read("wBlockCoreService/WebExtensionRequestHandler.swift")
let background = read("extension-src/background.js")
let preference = read("wBlockCoreService/DarkReaderAppearancePreference.swift")
let view = read("wBlock/UserScriptManagerView.swift")
let appSources = manager + preference
let urls = [
    "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/tube-cleaner/dist/tube-cleaner.user.js",
    "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/player-cleaner/dist/player-cleaner.user.js",
    "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/dark-reader/dist/dark-reader.user.js",
]
for url in urls { guard appSources.contains(url) else { fail("missing canonical URL \(url)") } }
let aliases = [
    "https://bundled.wblock.invalid/tube-cleaner.user.js": urls[0],
    "https://bundled.wblock.invalid/player-cleaner.user.js": urls[1],
    "https://bundled.wblock.invalid/dark-reader.user.js": urls[2],
]
for (legacy, canonical) in aliases {
    guard manager.contains("\"\(legacy)\": ") && cloud.contains("\"\(legacy)\": ")
        && appSources.contains(canonical) && cloud.contains(canonical)
    else { fail("missing legacy alias for \(legacy)") }
}
guard manager.contains("isEnabledByDefault: false") && manager.contains("isBeta: true") && manager.contains("displayRole: .functionality") else { fail("remote defaults lost beta/functionality/default-off contract") }
guard manager.contains("legacyBundledURLsByCanonical") && manager.contains("migrateLegacyBundledUserScriptsIfNeeded") else { fail("legacy migration missing") }
guard manager.contains("updatesAutomatically = true") else { fail("legacy scripts must become auto-updating") }
guard manager.contains("mergedDisabledHosts.formUnion")
    && manager.contains("if !canonicalWasConfigured")
    && manager.contains("$0.url?.absoluteString == legacyURL && $0.isEnabled")
    && manager.contains("removeUserScriptFile(duplicate)")
else { fail("duplicate migration must preserve explicit enablement, per-site state, and cached files") }
guard cloud.contains("legacyBundledURLs") && cloud.contains("bundled.wblock.invalid") else { fail("cloud aliases missing") }
guard !handler.contains("getDocumentStartUserScriptCatalog")
    && !handler.contains("documentStartCacheAllowed")
    && !handler.contains("cacheCategory")
    && !handler.contains("cacheRevision")
    && !manager.contains("enabledDocumentStartUserScriptsForCache")
else { fail("unreachable document-start catalog/cache contract remains") }
guard !manager.contains("bundledContent") && !manager.contains("BundledUserScriptSources") && !handler.contains("BundledUserScriptSources") else { fail("embedded source symbols remain") }
guard preference.contains("darkReaderFollowsSystemAppearance")
    && preference.contains("else { return true }")
    && preference.contains("__wblockDarkReaderFollowsSystemAppearance")
else { fail("Dark Reader preference must default on and configure runtime content") }
guard manager.contains("@Published public private(set) var darkReaderFollowsSystemAppearance")
    && manager.contains("setDarkReaderFollowsSystemAppearance")
    && manager.contains("invalidateDocumentStartExecutionCache")
else { fail("Dark Reader preference is not observable or cache-safe") }
guard view.contains("DarkReaderAppearancePicker")
    && view.contains("Follow System")
    && view.contains("Always Dark")
    && view.contains("if script.isDarkReader")
else { fail("Dark Reader appearance setting must use a compact list-row menu") }
guard handler.contains("configuredExecutableContent(for: script)")
    && handler.contains("dark-reader-\\(mode)")
    && handler.contains("DarkReaderAppearancePreference.followsSystemAppearance()")
else { fail("Dark Reader preference does not cover inline and chunked payloads") }
guard handler.contains("let injectInto = script.injectInto == \"auto\" && hasUnsafeWindowGrant")
    && handler.contains("descriptor[\"contentDigest\"]")
    && handler.contains("UserStylePreprocessorService.digest(")
else { fail("canonical Dark Reader descriptor must retain content injection and its digest") }
guard handler.contains("requestedContentDigest")
    && handler.contains("userscript-integrity-mismatch")
    && handler.contains("DarkReaderAppearancePreference.matches(scriptURL: script.url)")
    && background.contains("message.contentDigest")
else { fail("Dark Reader digest validation contract is missing") }
guard preference.contains("__wblockDarkReaderFollowsSystemAppearance")
    && !preference.contains("__wblockDarkReaderPreviousGlobal")
else { fail("Dark Reader preference must only prepend its configuration constant") }
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
    for key in [
        "Follow System",
        "Always Dark",
    ] {
        guard strings.contains("\"\(key)\" =") else { fail("Dark Reader setting localization missing in \(locale): \(key)") }
    }
    if locale != "en.lproj" {
        guard !strings.contains("\"\(description)\" = \"\(description)\";") else {
            fail("English Dark Reader description copied into \(locale)")
        }
    }
}
print("PASS: remote userscript migration contract")
