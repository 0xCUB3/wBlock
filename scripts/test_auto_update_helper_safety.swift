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

print("PASS: auto-update helper safety checks")
