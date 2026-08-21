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

let webExtension = try String(
    contentsOfFile: "wBlockCoreService/WebExtensionRequestHandler.swift",
    encoding: .utf8
)
let coreService = try String(
    contentsOfFile: "wBlockCoreService/wBlockCoreService.swift",
    encoding: .utf8
)
let appDisabledSites = try String(
    contentsOfFile: "wBlock/AppFilterManager+DisabledSites.swift",
    encoding: .utf8
)
let disabledSitesApplyStart = section(
    coreService,
    from: "public static func markDisabledSitesApplyStarted",
    to: "/// Clears one active Scripts-extension disabled-sites update marker."
)
let disabledSitesApplyRefresh = section(
    coreService,
    from: "public static func refreshDisabledSitesApplyInProgress",
    to: "/// Clears one active Scripts-extension disabled-sites update marker."
)
let disabledSitesApplyFinish = section(
    coreService,
    from: "public static func markDisabledSitesApplyFinished",
    to: "/// Returns whether a Scripts-extension disabled-sites update started recently."
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
let reloadTargets = section(
    webExtension,
    from: "private static func reloadTargetsWithRetry",
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
let disabledSitesApplySkip = section(
    appDisabledSites,
    from: "if ContentBlockerService.isDisabledSitesApplyInProgress(",
    to: "await ConcurrentLogManager.shared.info("
)

require(
    fastPath.contains("fastUpdateDisabledSitesWithOutputChange("),
    "disabled-sites fast path must observe whether its output changed"
)
require(
    !fastPath.contains("ContentBlockerService.markDisabledSitesApplyStarted(groupIdentifier: groupID)")
        && !fastPath.contains("ContentBlockerService.markDisabledSitesApplyFinished(groupIdentifier: groupID)"),
    "disabled-sites fast path must not change the persist-and-apply marker refcount"
)
if let refresh = fastPath.range(of: "ContentBlockerService.refreshDisabledSitesApplyInProgress(groupIdentifier: groupID)"),
   let reload = fastPath.range(of: "reloadTargetsWithRetry(targetsToReload)") {
    require(refresh.lowerBound < reload.lowerBound, "fast path must refresh its apply marker before Safari reload")
} else {
    fail("fast path must refresh its apply marker before Safari reload")
}
require(
    disabledSitesApplyRefresh.contains("startedAt: now")
        && disabledSitesApplyRefresh.contains("count: stamp.count")
        && disabledSitesApplyRefresh.contains("writeDisabledSitesApplyInProgressStamp")
        && coreService.contains("try? data.write(to: url, options: .atomic)"),
    "refresh must atomically update the timestamp without changing the refcount"
)
require(
    appDisabledSites.contains("ContentBlockerService.isDisabledSitesApplyInProgress("),
    "app disabled-sites monitor must consult the extension apply marker"
)
require(
    disabledSitesApplySkip.contains("scheduleDisabledSitesApplyRetry()"),
    "app disabled-sites monitor must retry after an extension apply is in progress"
)
require(
    !disabledSitesApplySkip.contains("fastApplyDisabledSitesChanges"),
    "extension apply marker must suppress app-side fast apply"
)
require(
    !disabledSitesApplySkip.contains("hasUnappliedChanges = true")
        && !disabledSitesApplySkip.contains("scheduleAutoApplyDebounce"),
    "extension apply marker must not schedule a full filter rebuild"
)
require(
    reloadTargets.contains("await ContentBlockerService.reloadIfNeeded("),
    "disabled-sites fast-path reloads must use reloadIfNeeded"
)
require(
    !reloadTargets.contains("await ContentBlockerService.reloadWithRetry("),
    "disabled-sites fast-path reloads must not invalidate markers with reloadWithRetry"
)
if let applyStart = setSiteDisabledState.range(of: "ContentBlockerService.markDisabledSitesApplyStarted(groupIdentifier: groupID)"),
   let persist = setSiteDisabledState.range(of: "await ProtobufDataManager.shared.setWhitelistedDomains(list)") {
    require(applyStart.lowerBound < persist.lowerBound, "site disabled state must mark apply started before persisting")
} else {
    fail("site disabled state must mark apply started before persisting")
}
require(
    setSiteDisabledState.contains("defer {")
        && setSiteDisabledState.contains("ContentBlockerService.markDisabledSitesApplyFinished(groupIdentifier: groupID)"),
    "site disabled state must clear its apply marker on every exit"
)
require(
    setSiteDisabledState.contains("\"requiresFullApply\": false"),
    "no-op site-toggle replies must include requiresFullApply"
)
require(
    setSiteDisabledState.contains("\"requiresFullApply\": summary.requiresFullApply"),
    "changed site-toggle replies must include requiresFullApply"
)
require(
    fastPath.contains("error.code == .fileReadCorruptFile"),
    "missing base-rules cache must request a full apply"
)
require(
    reloadContext.contains("sharedReloadIdentity()"),
    "reload context must use the shared app upgrade identity"
)
require(
    !reloadContext.contains("Bundle.main"),
    "reload context must not read process-specific Bundle.main metadata"
)
require(
    sharedReloadIdentity.contains("UserDefaults(suiteName: GroupIdentifier.shared.value)"),
    "shared reload identity must use app-group defaults"
)
require(
    sharedReloadIdentity.contains("if Bundle.main.bundleIdentifier == \"skula.wBlock\""),
    "only the containing app may publish reload identity"
)
if let publisher = sharedReloadIdentity.range(of: "if Bundle.main.bundleIdentifier == \"skula.wBlock\""),
   let versionWrite = sharedReloadIdentity.range(of: "defaults?.set(appVersion, forKey: reloadContextAppVersionKey)"),
   let buildWrite = sharedReloadIdentity.range(of: "defaults?.set(appBuild, forKey: reloadContextAppBuildKey)") {
    require(publisher.lowerBound < versionWrite.lowerBound && publisher.lowerBound < buildWrite.lowerBound, "reload identity writes must be app-only")
} else {
    fail("shared reload identity must publish version and build")
}
require(
    sharedReloadIdentity.contains("defaults?.string(forKey: reloadContextAppVersionKey) ?? \"\"")
        && sharedReloadIdentity.contains("defaults?.string(forKey: reloadContextAppBuildKey) ?? \"\""),
    "non-app processes must read reload identity from app-group defaults"
)
require(
    coreService.contains("disabledSitesApplyInProgressMaximumAge: TimeInterval = reloadCompletionTimeout * 6")
        || coreService.contains("disabledSitesApplyInProgressMaximumAge: TimeInterval = 180"),
    "disabled-sites apply marker must cover the full Safari retry window"
)
require(
    disabledSitesApplyStart.contains("count") && disabledSitesApplyFinish.contains("count"),
    "disabled-sites apply start and finish must maintain a refcount"
)

struct SimulatedApplyStamp {
    let startedAt: TimeInterval
    let count: Int
}

let simulatedMaximumAge: TimeInterval = 180
func simulatedApplyIsInProgress(_ stamp: SimulatedApplyStamp?, now: TimeInterval) -> Bool {
    guard let stamp else { return false }
    let age = now - stamp.startedAt
    return age >= 0 && age < simulatedMaximumAge
}

func simulatedMarkApplyStarted(_ stamp: inout SimulatedApplyStamp?, now: TimeInterval) {
    let count = simulatedApplyIsInProgress(stamp, now: now) ? stamp!.count + 1 : 1
    stamp = SimulatedApplyStamp(startedAt: now, count: count)
}

func simulatedMarkApplyFinished(_ stamp: inout SimulatedApplyStamp?, now: TimeInterval) {
    guard let existing = stamp, simulatedApplyIsInProgress(existing, now: now) else {
        stamp = nil
        return
    }
    let count = existing.count - 1
    stamp = count > 0 ? SimulatedApplyStamp(startedAt: existing.startedAt, count: count) : nil
}

func simulatedRefreshApplyInProgress(_ stamp: inout SimulatedApplyStamp?, now: TimeInterval) {
    guard let existing = stamp, simulatedApplyIsInProgress(existing, now: now) else {
        return
    }
    stamp = SimulatedApplyStamp(startedAt: now, count: existing.count)
}

var simulatedStamp: SimulatedApplyStamp?
simulatedMarkApplyStarted(&simulatedStamp, now: 1_000)
simulatedRefreshApplyInProgress(&simulatedStamp, now: 1_010)
require(
    simulatedStamp?.count == 1 && simulatedStamp?.startedAt == 1_010,
    "refresh must preserve one active refcount while updating its timestamp"
)
simulatedMarkApplyFinished(&simulatedStamp, now: 1_011)
require(simulatedStamp == nil, "one finish must clear a refreshed single-count stamp")


simulatedMarkApplyStarted(&simulatedStamp, now: 1_000) // A starts.
simulatedMarkApplyStarted(&simulatedStamp, now: 1_001) // B starts.
simulatedMarkApplyFinished(&simulatedStamp, now: 1_002) // A finishes.
require(
    simulatedApplyIsInProgress(simulatedStamp, now: 1_002),
    "finishing A must not clear B's in-progress stamp"
)
simulatedMarkApplyFinished(&simulatedStamp, now: 1_003) // B finishes.
require(
    !simulatedApplyIsInProgress(simulatedStamp, now: 1_003),
    "finishing B must clear the last in-progress stamp"
)
simulatedStamp = SimulatedApplyStamp(startedAt: 800, count: 4)
require(
    !simulatedApplyIsInProgress(simulatedStamp, now: 1_000),
    "a stale apply stamp must not remain in progress"
)
simulatedMarkApplyStarted(&simulatedStamp, now: 1_000)
require(simulatedStamp?.count == 1, "starting over a stale stamp must reset its refcount")
simulatedMarkApplyFinished(&simulatedStamp, now: 1_001)
require(simulatedStamp == nil, "one finish must clear a reset stale stamp")

print("PASS: site toggle fast-path contract")
