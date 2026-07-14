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
let settingsView = try read("wBlock/SettingsView.swift")
let buildDMG = try read("scripts/build-dmg.sh")

assertContains(
    service,
    "reply(outcome.isSuccessfulForBackgroundTask)",
    "XPC service must propagate the actual update outcome"
)
assertNotContains(
    service,
    "reply(true)",
    "XPC service must not report success unconditionally"
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

print("PASS: auto-update helper safety checks")
