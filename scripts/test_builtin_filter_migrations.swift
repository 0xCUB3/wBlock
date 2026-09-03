#!/usr/bin/env swift

import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let loader = try String(contentsOfFile: "wBlock/FilterListLoader.swift", encoding: .utf8)
let manager = try String(contentsOfFile: "wBlock/AppFilterManager.swift", encoding: .utf8)
let sync = try String(contentsOfFile: "wBlock/CloudSyncManager.swift", encoding: .utf8)

let migrations = [
    ("Online Security Filter", "Online Malicious URL Blocklist"),
    ("Anti-Adblock List", "Adblock Warning Removal List"),
    ("Fanboy's Anti-AI Suggestions", "Stevo's AI Blocklist"),
    ("Hagezi Pro Mini", "HaGeZi Pro Mini"),
    ("List-KR", "filterslists-KO"),
]
for (oldName, newName) in migrations {
    expect(loader.contains("\"\(newName)\": [\"\(oldName)\"]"), "missing built-in name migration for \(oldName)")
}
expect(loader.contains("migrateBuiltInFilterFilesIfNeeded"), "built-in cache migration is not defined")
expect(loader.contains("prefix: \"diff-baseline-\""), "built-in delta baselines are not migrated")
expect(loader.contains("name: oldName"), "offline filter cache is not migrated safely")
// Fanboy's Anti-AI content came from a different source than Stevo's AI Blocklist
// (#637); the legacy cache must be dropped rather than renamed into the new entry.
expect(loader.contains("\"Fanboy's Anti-AI Suggestions\": \"! Title: Fanboy's Anti-AI\""), "replaced-source legacy cache is still carried over")
expect(loader.contains("if header.contains(legacyTitle)"), "already carried-over replaced-source cache is not dropped")
expect(loader.contains("replacedSource ? nil : newLocalURL"), "replaced-source legacy cache is not deleted")
expect(manager.contains("loader.migrateBuiltInFilterFilesIfNeeded(defaultFilter)"), "built-in cache migration is not run during setup")
expect(loader.contains("static func canonicalFilterURLString"), "filter URL canonicalization is not exposed")
expect(sync.contains("FilterListLoader.canonicalFilterURLString"), "CloudSync does not canonicalize filter URLs")
expect(sync.contains("map { FilterListLoader.canonicalFilterURLString($0.url.absoluteString) }"), "CloudSync payload does not use canonical filter identity")

let compactLoader = loader.components(separatedBy: .whitespacesAndNewlines).joined()
let optimizedURLMigrations = [
    ("260.txt", "260_optimized.txt", "Stevo'sAIBlocklist"),
    ("25.txt", "25_optimized.txt", "MailTrackingProtectionFilter"),
    ("10.txt", "10_optimized.txt", "AdGuardAllowlist"),
]
let adGuardSafariPrefix = "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/"
for (oldFilename, newFilename, compactName) in optimizedURLMigrations {
    let oldURL = adGuardSafariPrefix + oldFilename
    let newURL = adGuardSafariPrefix + newFilename
    expect(
        compactLoader.contains("\"\(oldURL)\":URL(string:\"\(newURL)\")!"),
        "missing optimized URL migration for \(oldFilename)"
    )
    expect(
        compactLoader.contains("name:\"\(compactName)\",url:URL(string:\"\(newURL)\")!"),
        "default catalog does not use \(newFilename)"
    )
}

print("PASS")
