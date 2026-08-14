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
expect(manager.contains("loader.migrateBuiltInFilterFilesIfNeeded(defaultFilter)"), "built-in cache migration is not run during setup")
expect(loader.contains("static func canonicalFilterURLString"), "filter URL canonicalization is not exposed")
expect(sync.contains("FilterListLoader.canonicalFilterURLString"), "CloudSync does not canonicalize filter URLs")
expect(sync.contains("map { FilterListLoader.canonicalFilterURLString($0.url.absoluteString) }"), "CloudSync payload does not use canonical filter identity")

print("PASS")
