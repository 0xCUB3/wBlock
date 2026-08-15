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

let service = try read("FilterUpdateService/FilterUpdateService.swift")
let runner = try read("wBlockCoreService/FilterAutoUpdateRunner.swift")
let agentEntitlements = try read("FilterUpdateAgent/FilterUpdateAgent.entitlements")
let groupIdentifier = try read("wBlockCoreService/GroupIdentifier.swift")
let sharedAutoUpdate = try read("wBlockCoreService/SharedAutoUpdateManager.swift")
let logManager = try read("wBlock/ConcurrentLogManager.swift")
let settingsView = try read("wBlock/SettingsView.swift")
let buildDMG = try read("scripts/build-dmg.sh")

assertContains(
    service,
    "reply(outcome.isSuccessfulForBackgroundTask)",
    "XPC service must propagate the actual update outcome"
)
let updateFiltersImplementation = service.components(separatedBy: "func startFilterUpdate").first ?? service
assertNotContains(
    updateFiltersImplementation,
    "reply(true)",
    "XPC updateFilters must not report success unconditionally"
)
assertContains(
    runner,
    "return outcome.isSuccessfulForBackgroundTask",
    "Launch-agent fallback must propagate failed/deferred/cancelled outcomes"
)
assertContains(
    agentEntitlements,
    "com.apple.security.application-groups",
    "Launch agent fallback needs app-group access to shared filter state"
)
assertContains(
    agentEntitlements,
    "group.skula.wBlock",
    "Launch agent fallback must use the wBlock app group"
)
assertContains(
    agentEntitlements,
    "com.apple.security.network.client",
    "Launch agent fallback needs network access to fetch filters"
)
assertContains(
    groupIdentifier,
    "SecTaskCopyValueForEntitlement",
    "Launch agent must derive direct-distribution app group from its own entitlements"
)
assertContains(
    groupIdentifier,
    "com.apple.security.application-groups",
    "Launch agent must inspect app-group entitlements before falling back to Info.plist"
)
assertContains(
    groupIdentifier,
    "prefix.contains(\"$(\")",
    "Unpatched AppIdentifierPrefix placeholders must not be used as app-group identifiers"
)
assertContains(
    buildDMG,
    "Delete :com.apple.security.application-groups",
    "Direct-distribution signing must remove unprovisioned group.* app groups"
)
assertContains(
    buildDMG,
    "Add :com.apple.security.application-groups:0 string ${TEAM_GROUP}",
    "Direct-distribution signing must keep only the TeamID-prefixed app group"
)
assertNotContains(
    buildDMG,
    "Add :com.apple.security.application-groups: string ${TEAM_GROUP}",
    "Direct-distribution signing must not add the TeamID group alongside the legacy group"
)
assertContains(
    sharedAutoUpdate,
    "selectedFilterStateUnavailable",
    "Helper runs must fail closed when selected-filter state is suspiciously empty"
)
assertContains(
    sharedAutoUpdate,
    "contentBlockerOutputsContainRules()",
    "Suspicious empty state should be checked against existing blocker output"
)
assertContains(
    sharedAutoUpdate,
    "throw AutoUpdateError.contentBlockerReloadFailed",
    "Failed Safari reloads must not be counted as successful background runs"
)
assertNotContains(
    sharedAutoUpdate,
    "reloadStatus = reloaded ? \"ok\" : \"failed\"",
    "Reload failure should throw instead of being logged as a completed run"
)

assertContains(
    sharedAutoUpdate,
    "private var runInProgress = false",
    "Actor-local state must serialize reentrant auto-update triggers"
)
assertContains(
    sharedAutoUpdate,
    "defer { runInProgress = false }",
    "Every auto-update exit must release the actor-local run claim"
)
assertContains(
    sharedAutoUpdate,
    "boundedConcurrentForEach(remoteFilters",
    "Background fetches must be limited to remotely fetchable filters with bounded concurrency"
)
assertContains(
    sharedAutoUpdate,
    "checkedCount: remoteFilters.count",
    "Update telemetry must count only remotely fetchable filters"
)

assertContains(
    sharedAutoUpdate,
    "await ProtobufDataManager.shared.setAutoUpdateForceNext(true)",
    "Deferred background work must force the next foreground auto-update"
)
assertContains(
    settingsView,
    "case .deferred:\n            return String(localized: \"Deferred\")",
    "Deferred background work must not be presented as a failure"
)

assertContains(
    sharedAutoUpdate,
    "if isExternalHelperTrigger(trigger)",
    "External helpers must hand blocker reloads back to the app"
)
assertContains(
    sharedAutoUpdate,
    "reloadStatus = \"pending app launch\"",
    "A helper reload handoff must be recorded as pending rather than failed"
)
assertContains(
    sharedAutoUpdate,
    "reloadContentBlockers: !helperStagedUpdates",
    "External helpers must compile outputs without calling SafariServices reloads"
)
assertContains(
    sharedAutoUpdate,
    "if reloadContentBlockers {",
    "Safari content blocker reloads must be guarded by app-process ownership"
)
assertContains(
    sharedAutoUpdate,
    "helperStagedUpdates ? \"staged_updates\" : \"applied_updates\"",
    "Successfully staged helper updates must not emit a failed outcome"
)
assertContains(
    sharedAutoUpdate,
    "result: helperStagedUpdates ? .stagedUpdates : .appliedUpdates",
    "The XPC service must report successful staging without triggering fallback"
)
assertContains(
    sharedAutoUpdate,
    "if reloadStatus == \"ok\" || scriptsResult.updated > 0",
    "The app-owned reload must refresh the last-success timestamp"
)

assertContains(
    logManager,
    "LocalizedStrings.format(\"Auto-update: %@\", outcome)",
    "Auto-update outcomes must not expose the internal telemetry label"
)
assertNotContains(
    logManager,
    "LocalizedStrings.format(\"Telemetry: %@\", outcome)",
    "The log UI must not call update outcomes telemetry"
)
assertContains(
    logManager,
    "fields[\"phase\"] == \"content blocker reload\"",
    "Obsolete helper reload failures must be excluded during ingestion"
)

let localizationRoot = URL(fileURLWithPath: "wBlock")
for locale in try FileManager.default.contentsOfDirectory(at: localizationRoot, includingPropertiesForKeys: nil)
    .filter({ $0.pathExtension == "lproj" }) {
    let strings = try read(locale.appendingPathComponent("Localizable.strings").path)
    assertContains(strings, "\"Auto-update: %@\" =", "Missing localized auto-update log label in \(locale.lastPathComponent)")
}

assertContains(
    sharedAutoUpdate,
    "clearPersistedBlockingOutputsForPause(reloadContentBlockers: !helperStagedOutputs)",
    "Paused helper runs must stage inert outputs without reloading Safari blockers"
)
assertContains(
    sharedAutoUpdate,
    "Failed to clear paused advanced engine during auto-update: \\(error.localizedDescription)\")\n            return false",
    "A failed or superseded advanced-engine clear must stop paused output repair"
)
assertContains(
    sharedAutoUpdate,
    "Failed to clear paused removeparam rules during auto-update: \\(error.localizedDescription)\")\n            return false",
    "Failed removeparam cleanup must stop paused output repair"
)
assertContains(
    sharedAutoUpdate,
    "if helperStagedOutputs && repairedOutputs",
    "Paused helper staging must force the next app-owned reload"
)
assertContains(
    logManager,
    "if shouldIgnoreLegacyHelperReloadFailure(parsed.body) { continue }",
    "Raw legacy helper reload failures must be hidden as well as telemetry failures"
)

func ignoresLegacyHelperReloadFailure(_ body: String) -> Bool {
    let normalized = body.replacingOccurrences(of: "_", with: " ")
    let helperTriggers = ["XPCService", "LaunchAgent", "LegacyLoginItem"]
    return normalized.contains("Auto-update failed:")
        && normalized.contains("phase=content blocker reload")
        && helperTriggers.contains { normalized.contains("trigger=\($0)") }
}

guard ignoresLegacyHelperReloadFailure(
    "Auto-update failed: trigger=XPCService, phase=content_blocker_reload, reason=reload denied"
) else {
    fputs("FAIL: raw XPC reload failure should be suppressed\n", stderr)
    exit(1)
}
guard !ignoresLegacyHelperReloadFailure(
    "Auto-update failed: trigger=AppLaunch, phase=content_blocker_reload, reason=reload denied"
) else {
    fputs("FAIL: genuine app reload failure must remain visible\n", stderr)
    exit(1)
}

assertContains(
    logManager,
    "if !represented {\n                log(level, .autoUpdate, parsed.body",
    "Mixed logs must retain raw app failures that have no structured result"
)

print("PASS: auto-update helper safety checks")
