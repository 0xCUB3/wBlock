#!/usr/bin/env swift

import Foundation

let manager = try String(
    contentsOfFile: "wBlockCoreService/UserScriptManager.swift",
    encoding: .utf8
)
let contentView = try String(
    contentsOfFile: "wBlock/ContentView.swift",
    encoding: .utf8
)
let userscriptView = try String(
    contentsOfFile: "wBlock/UserScriptManagerView.swift",
    encoding: .utf8
)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

require(
    contentView.components(separatedBy: "LazyVStack").count >= 3,
    "macOS filter rows should be rendered lazily"
)
require(
    !contentView.contains("LazyVStack(spacing: 20) {\n                statsCardsView"),
    "macOS filter section containers must not be lazy; nested lazy stacks jump and drop rows"
)
require(
    manager.components(separatedBy: "hydrateDisabled: false").count >= 2,
    "startup and synchronization should keep disabled userscript payloads on disk"
)
require(
    manager.contains("userScriptEditorSnapshot(withId id: UUID) async")
        && manager.contains("Self.hydrateUserScriptFromDisk(script)"),
    "userscript content should remain available through on-demand hydration"
)
require(
    manager.contains("hasDownloadedContent(for userScript: UserScript)")
        && userscriptView.contains("userScriptManager.hasDownloadedContent(for: script)"),
    "disk-backed scripts should still appear downloaded"
)
require(
    (manager.contains("hydrateUserScriptsFromDisk(userScripts, includeResources: true)")),
    "backups should hydrate disabled userscript source and resources"
)

let userScriptModel = try String(
    contentsOfFile: "wBlockCoreService/UserScript.swift",
    encoding: .utf8
)
require(
    userScriptModel.contains("countLimit: Int = 2, totalCostLimit: Int = 8 * 1024 * 1024"),
    "Safari userscript payload caching should have a bounded idle footprint"
)

for field in ["matches", "excludeMatches", "includes", "excludes", "grant"] {
    require(
        manager.contains("\\.\(field)"),
        "reparsed \(field) metadata should reuse persisted storage when unchanged"
    )
}
require(
    manager.contains("hydratedScript[keyPath: keyPath] = script[keyPath: keyPath]"),
    "unchanged parsed metadata should reuse protobuf-backed arrays"
)

print("PASS: idle memory contracts")
