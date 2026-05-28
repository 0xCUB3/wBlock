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

func assertNotContains(_ haystack: String, _ needle: String, _ message: String) {
    guard !haystack.contains(needle) else {
        fputs("FAIL: \(message)\nUnexpected: \(needle)\n", stderr)
        exit(1)
    }
}

let intent = try read("wBlock/FilterUpdateShortcuts.swift")
let progressViewModel = try read("wBlock/ApplyChangesViewModel.swift")
let progressView = try read("wBlock/ApplyChangesProgressView.swift")
let contentView = try read("wBlock/ContentView.swift")
let project = try read("wBlock.xcodeproj/project.pbxproj")
let fileManager = FileManager.default
let localizationRoot = URL(fileURLWithPath: "wBlock")
let localizationKeys = [
    "Update wBlock Filters",
    "Checks for wBlock filter updates and applies them when available.",
    "wBlock filter update started.",
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
    "Shortcut update must run with the app opened to show the normal apply flow"
)
assertNotContains(
    intent,
    "@Parameter",
    "Shortcut update must not expose a force option"
)
assertNotContains(
    intent,
    "forceCheck",
    "Shortcut update must always use the forced apply path"
)
assertContains(
    intent,
    "@MainActor\n    func perform()",
    "Shortcut intent must run its request handoff on the main actor"
)
assertContains(
    intent,
    "IntentDialog(\"wBlock filter update started.\")",
    "Shortcut intent dialog must be explicitly localized"
)
assertContains(
    intent,
    "ShortcutFilterUpdateRequest.shared.requestUpdate()",
    "Shortcut must request the app to run the normal apply flow"
)
assertNotContains(
    intent,
    "maybeRunAutoUpdate(",
    "Shortcut must not use a separate shared auto-update UI path"
)
assertContains(
    intent,
    "struct WBlockShortcutsProvider: AppShortcutsProvider",
    "Shortcut must be discoverable in Shortcuts"
)
assertContains(
    contentView,
    "shortcutFilterUpdateRequested",
    "Main view must listen for shortcut update requests"
)
assertContains(
    contentView,
    "checkAndEnableFilters(forceReload: true)",
    "Shortcut must use the same forced apply entry point as Apply Changes"
)
assertContains(
    contentView,
    "applyFilterChangesFromExternalTrigger()",
    "Notification and shortcut triggers must share one apply path"
)
assertNotContains(
    contentView,
    "await filterManager.checkAndEnableFilters(forceReload: true)",
    "External triggers should call the synchronous apply entry point directly"
)
assertNotContains(
    progressViewModel,
    "prepareShortcutFilterUpdate",
    "Shortcut must not add a separate progress state"
)
assertNotContains(
    progressView,
    "completionCard(",
    "Shortcut must not add a separate completion UI"
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
