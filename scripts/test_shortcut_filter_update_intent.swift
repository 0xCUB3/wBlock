#!/usr/bin/env swift

import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func assertContains(_ haystack: String, _ needle: String, _ message: String) {
    guard haystack.contains(needle) else {
        fputs("FAIL: \(message)\nMissing: \(needle)\n", stderr)
        exit(1)
    }
}

let intent = try read("wBlock/FilterUpdateShortcuts.swift")
let project = try read("wBlock.xcodeproj/project.pbxproj")
let fileManager = FileManager.default
let localizationRoot = URL(fileURLWithPath: "wBlock")
let localizationKeys = [
    "Update wBlock Filters",
    "Checks for wBlock filter updates and applies them when available.",
    "Force Check",
    "Check now even if automatic updates are not due yet.",
    "wBlock filters updated.",
    "No filter updates found.",
    "wBlock filter update skipped because it is not due yet.",
    "wBlock filter update failed. Open wBlock for details.",
    "Update Filters",
]

assertContains(
    intent,
    "struct UpdateWBlockFiltersIntent: AppIntent",
    "Shortcut intent must expose the update action through App Intents"
)
assertContains(
    intent,
    "static var openAppWhenRun: Bool { true }",
    "Shortcut update must run with the app opened to avoid a silent long background job"
)
assertContains(
    intent,
    "maybeRunAutoUpdate(",
    "Shortcut update must use the shared auto-update pipeline"
)
assertContains(
    intent,
    "policy: .foreground(trigger: trigger)",
    "Shortcut update must use the foreground auto-update policy"
)
assertContains(
    intent,
    "struct WBlockShortcutsProvider: AppShortcutsProvider",
    "Shortcut must be discoverable in Shortcuts"
)
assertContains(
    project,
    "PBXFileSystemSynchronizedRootGroup",
    "Project must use synchronized groups so new app files are picked up automatically"
)

let localizationFiles = try fileManager.contentsOfDirectory(
    at: localizationRoot,
    includingPropertiesForKeys: nil
).filter { $0.pathExtension == "lproj" }
 .map { $0.appendingPathComponent("Localizable.strings") }
 .filter { fileManager.fileExists(atPath: $0.path) }

for file in localizationFiles {
    let strings = try read(file.path)
    for key in localizationKeys {
        assertContains(strings, "\"\(key)\" =", "Missing shortcut localization key in \(file.path)")
    }
}

print("PASS: shortcut filter update intent checks")
