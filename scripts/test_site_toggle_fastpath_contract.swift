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
    fastPath.contains("ContentBlockerService.markDisabledSitesApplyStarted(groupIdentifier: groupID)"),
    "disabled-sites fast path must mark its cross-process apply as started"
)
require(
    fastPath.contains("ContentBlockerService.markDisabledSitesApplyFinished(groupIdentifier: groupID)"),
    "disabled-sites fast path must clear its cross-process apply marker"
)
require(
    fastPath.contains("defer {"),
    "disabled-sites fast path must clear its apply marker on every exit"
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
require(
    setSiteDisabledState.contains("await ProtobufDataManager.shared.setWhitelistedDomains(list)"),
    "site disabled state must persist through setWhitelistedDomains"
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
    !reloadContext.contains("Bundle.main"),
    "reload context must not read process-specific Bundle.main metadata"
)
require(
    !reloadContext.contains("CFBundleShortVersionString")
        && !reloadContext.contains("CFBundleVersion"),
    "reload context must not use process-specific version or build metadata"
)

print("PASS: site toggle fast-path contract")
