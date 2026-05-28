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
let progressViewModel = try read("wBlock/ApplyChangesViewModel.swift")
let progressView = try read("wBlock/ApplyChangesProgressView.swift")
let contentView = try read("wBlock/ContentView.swift")
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
    "Updating wBlock Filters",
    "Checking for filter updates...",
    "wBlock Filters Updated",
    "No Filter Updates",
    "Filter Update Skipped",
    "Filter Update Deferred",
    "Filter Update Failed",
    "Filter Update Cancelled",
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
    intent,
    "ShortcutFilterUpdatePresentation.shared.start()",
    "Shortcut must announce start so the opened app shows visible progress"
)
assertContains(
    intent,
    "ShortcutFilterUpdatePresentation.shared.finish(",
    "Shortcut must announce completion so the progress sheet shows the result"
)
assertContains(
    contentView,
    "shortcutFilterUpdatePresentationChanged",
    "Main view must listen for shortcut progress presentation changes"
)
assertContains(
    contentView,
    "prepareShortcutFilterUpdate()",
    "Main view must show the apply-style sheet while shortcut updates run"
)
assertContains(
    progressViewModel,
    "func completeShortcutFilterUpdate(",
    "Progress view model must support shortcut completion states"
)
assertContains(
    progressView,
    "completionCard(",
    "Apply progress sheet must render shortcut completion results"
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
