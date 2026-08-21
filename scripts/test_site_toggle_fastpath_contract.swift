#!/usr/bin/env swift

import Foundation

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func require(_ condition: Bool, _ message: String) {
    if !condition { fail(message) }
}

func section(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
    else { fail("missing source section: \(start)") }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

func requireBefore(_ first: String, _ second: String, in source: String, _ message: String) {
    guard let firstRange = source.range(of: first),
          let secondRange = source.range(of: second)
    else { fail("missing source-order marker: \(message)") }
    require(firstRange.lowerBound < secondRange.lowerBound, message)
}

let webExtension = try String(
    contentsOfFile: "wBlockCoreService/WebExtensionRequestHandler.swift",
    encoding: .utf8
)
let coreService = try String(
    contentsOfFile: "wBlockCoreService/wBlockCoreService.swift",
    encoding: .utf8
)
let setSiteDisabledState = section(
    webExtension,
    from: "private static func handleSetSiteDisabledState",
    to: "private static func handleGetBlockingPausedState"
)
let fastPath = section(
    webExtension,
    from: "private static func applyDisabledSitesFastPath",
    to: "/// Returns enabled userscripts"
)
let sharedReloadIdentity = section(
    coreService,
    from: "private static func sharedReloadIdentity",
    to: "private static var currentReloadContext"
)
let reloadContext = section(
    coreService,
    from: "private static var currentReloadContext",
    to: "private static func reloadMarkerURL"
)

requireBefore(
    "ContentBlockerService.markDisabledSitesApplyStarted(groupIdentifier: groupID)",
    "await ProtobufDataManager.shared.setWhitelistedDomains(list)",
    in: setSiteDisabledState,
    "site disabled state must mark apply started before persisting"
)
require(
    setSiteDisabledState.contains("defer {")
        && setSiteDisabledState.contains("ContentBlockerService.markDisabledSitesApplyFinished(groupIdentifier: groupID)"),
    "site disabled state must clear its apply marker on every exit"
)
require(
    !fastPath.contains("markDisabledSitesApplyStarted")
        && !fastPath.contains("markDisabledSitesApplyFinished")
        && !fastPath.contains("refreshDisabledSitesApplyInProgress"),
    "disabled-sites fast path must not manage the apply marker"
)
require(
    fastPath.contains("fastUpdateDisabledSitesWithOutputChange(")
        && fastPath.contains("await ContentBlockerService.reloadIfNeeded("),
    "disabled-sites fast path must update changed output and reload it if needed"
)
require(
    fastPath.contains("error.code == .fileReadCorruptFile")
        && fastPath.contains("requiresFullApply: fullApplyTargets > 0"),
    "missing base-rules cache must request a full apply"
)
require(
    reloadContext.contains("sharedReloadIdentity()") && !reloadContext.contains("Bundle.main"),
    "reload context must use the shared identity rather than process metadata"
)
require(
    sharedReloadIdentity.contains("if Bundle.main.bundleIdentifier == \"skula.wBlock\"")
        && sharedReloadIdentity.contains("UserDefaults(suiteName: GroupIdentifier.shared.value)")
        && sharedReloadIdentity.contains("defaults?.set(appVersion, forKey: reloadContextAppVersionKey)")
        && sharedReloadIdentity.contains("defaults?.set(appBuild, forKey: reloadContextAppBuildKey)")
        && sharedReloadIdentity.contains("defaults?.string(forKey: reloadContextAppVersionKey) ?? \"\"")
        && sharedReloadIdentity.contains("defaults?.string(forKey: reloadContextAppBuildKey) ?? \"\""),
    "shared reload identity must publish only from the app and read group defaults otherwise"
)
requireBefore(
    "if Bundle.main.bundleIdentifier == \"skula.wBlock\"",
    "defaults?.set(appVersion, forKey: reloadContextAppVersionKey)",
    in: sharedReloadIdentity,
    "only the containing app may publish reload identity"
)
requireBefore(
    "if Bundle.main.bundleIdentifier == \"skula.wBlock\"",
    "defaults?.set(appBuild, forKey: reloadContextAppBuildKey)",
    in: sharedReloadIdentity,
    "only the containing app may publish reload identity"
)
require(
    coreService.contains("disabledSitesApplyInProgressMaximumAge: TimeInterval = reloadCompletionTimeout * 6"),
    "disabled-sites apply marker must cover the full Safari retry window"
)

print("PASS: site toggle fast-path contract")
