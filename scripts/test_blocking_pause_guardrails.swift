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

let contentBlockerHandler = try read("wBlockCoreService/ContentBlockerExtensionRequestHandler.swift")
let webExtensionHandler = try read("wBlockCoreService/WebExtensionRequestHandler.swift")
let autoUpdateManager = try read("wBlockCoreService/SharedAutoUpdateManager.swift")
let appDelegate = try read("wBlock/AppDelegate.swift")
let removeParamGenerator = try read("wBlockCoreService/RemoveParamDNRRuleGenerator.swift")
let applyPipeline = try read("wBlock/AppFilterManager+ApplyPipeline.swift")
let contentBlockerService = try read("wBlockCoreService/wBlockCoreService.swift")
let backgroundSource = try read("extension-src/background.js")
let contentSource = try read("extension-src/content.js")
let popupSource = try read("wBlock Scripts (iOS)/Resources/pages/popup/popup.js")

assertContains(
    contentBlockerHandler,
    "BlockingPauseStore.isContentBlockingPaused(groupIdentifier: groupIdentifier)",
    "Content blocker extensions must serve inert rules directly while blocking is paused"
)
assertContains(
    contentBlockerHandler,
    "ContentBlockerService.inertContentBlockerRulesJSON",
    "Content blocker extensions must avoid literal empty arrays while blocking is paused"
)
assertContains(
    contentBlockerService,
    "public static let inertContentBlockerRulesJSON",
    "Pause mode needs a valid no-op content blocker payload"
)
assertContains(
    webExtensionHandler,
    "private static func emptyRulesPayload(disabled: Bool, paused: Bool)",
    "InitContentScript empty payloads must declare native disabled and paused state"
)
assertContains(
    webExtensionHandler,
    "\"disabled\": disabled,\n            \"paused\": paused",
    "InitContentScript payloads must carry both native state fields"
)
assertContains(
    webExtensionHandler,
    "message?[\"payload\"] = emptyRulesPayload(disabled: false, paused: true)",
    "Advanced WebExtension lookups must return paused state with inert rules"
)
assertContains(
    webExtensionHandler,
    "message?[\"payload\"] = nil",
    "Native configuration failures must not echo the request as a configuration"
)
assertContains(
    webExtensionHandler,
    "message?[\"state\"] = \"error\"",
    "Native configuration failures must use an explicit error state"
)
assertContains(
    webExtensionHandler,
    "message?[\"payload\"] = emptyRulesPayload(disabled: true, paused: false)",
    "Advanced WebExtension lookups must return disabled state with inert rules"
)
assertContains(
    webExtensionHandler,
    "payload[\"disabled\"] = disabled\n        payload[\"paused\"] = paused",
    "Normal native configurations must carry authoritative state"
)
assertContains(
    webExtensionHandler,
    "message?[\"payload\"] = convertToPayload(\n                                        configuration,\n                                        disabled: false,\n                                        paused: false\n                                    )",
    "Enabled InitContentScript configurations must declare active state"
)
assertContains(
    webExtensionHandler,
    "payload = RemoveParamDNRRuleGenerator.emptyRulesPayload(offset: offset, limit: limit)",
    "Removeparam DNR requests must return an empty payload while blocking is paused"
)
assertContains(
    webExtensionHandler,
    "case \"getBlockingPausedState\":",
    "Toolbar state must be able to query the global pause state"
)
assertContains(
    webExtensionHandler,
    "case \"getBlockingState\":",
    "Cached configurations must be able to query combined blocking state"
)
assertContains(
    webExtensionHandler,
    "\"disabled\": disabled, \"paused\": paused",
    "Combined blocking state must include site disable and global pause"
)
assertContains(
    removeParamGenerator,
    "public static func emptyRulesPayload(offset: Int, limit: Int) -> [String: Any]",
    "Removeparam DNR needs a stable empty payload for pause mode"
)
assertContains(
    autoUpdateManager,
    "return .skipped(reason: \"blocking_paused\")",
    "Auto-update must not rebuild real rules while blocking is paused"
)
assertContains(
    autoUpdateManager,
    "clearPersistedBlockingOutputsForPause(reloadContentBlockers: !helperStagedOutputs)",
    "Auto-update should repair paused outputs while reserving Safari reloads for the app"
)
assertContains(
    applyPipeline,
    "let platformTargets = ContentBlockerTargetManager.shared.allTargets(",
    "Pause clearing must enumerate every blocker target before writing inert rules"
)
assertContains(
    applyPipeline,
    "for targetInfo in platformTargets {",
    "Pause clearing must write every blocker target before reload failures can abort the pass"
)
assertContains(
    applyPipeline,
    "var reloadFailures: [String] = []",
    "Pause clearing should collect reload failures after all blocker outputs are replaced"
)
assertContains(
    applyPipeline,
    "jsonRules: ContentBlockerService.inertContentBlockerRulesJSON",
    "Pause clearing must write the inert content blocker payload instead of []"
)
assertContains(
    applyPipeline,
    "BlockingPauseStore.setPaused(true)",
    "Pause clearing must persist the paused state before replacing blocker outputs"
)
assertContains(
    applyPipeline,
    "reloadIfNeeded(",
    "Pause clearing must verify each target through the reload-skip coordinator"
)
assertNotContains(
    applyPipeline,
    "jsonRules: \"[]\"",
    "Pause clearing must not regress to a literal empty blocker list"
)
assertContains(
    applyPipeline,
    "let allSelectedFilters = pausedComponents.contains(.filters)",
    "Filter apply must omit filter lists only when Filters is paused"
)
assertContains(
    applyPipeline,
    "let generatedZapperRules = pausedComponents.contains(.elementZapper)",
    "Filter apply must omit generated zapper rules only when Element Zapper is paused"
)
assertContains(
    applyPipeline,
    "await applyChangesUnlocked(\n                allowUserInteraction: false,\n                prepareState: true,\n                skipPreApplyUpdates: false,\n                allowPausedResume: true",
    "Resuming blocking must use the standard visible apply pipeline"
)
assertNotContains(
    applyPipeline,
    "        } else {\n            await applyChanges(allowUserInteraction: true)\n            await MainActor.run {",
    "Resuming blocking must not suppress standard apply progress"
)
assertContains(
    appDelegate,
    "func applicationWillBecomeActive(_ notification: Notification) {\n        guard !BlockingPauseStore.isPaused(.filters) else { return }\n\n        // Check if update is overdue when app becomes active\n        Task {",
    "macOS foreground activation must skip opportunistic updates while blocking is paused"
)
assertContains(
    appDelegate,
    "func applicationDidBecomeActive(_ application: UIApplication) {\n        guard !BlockingPauseStore.isPaused(.filters) else { return }\n\n        // Run opportunistic updates only when app is active (not during background launches).\n        Task {",
    "Foreground activation must skip opportunistic updates while blocking is paused"
)
assertContains(
    backgroundSource,
    "typeof configuration.disabled === \"boolean\"",
    "Background InitContentScript responses must preserve native state"
)
assertContains(
    backgroundSource,
    "action: \"getBlockingPausedState\"",
    "Toolbar action state must query pause state from native storage"
)
assertContains(
    backgroundSource,
    "action: \"getBlockingState\"",
    "Cached configurations must use the priority combined-state lookup"
)
assertContains(
    backgroundSource,
    "const { configuration: cachedConfiguration, fromCache } = configurationResult;",
    "Configuration responses must retain cache provenance"
)
assertContains(
    backgroundSource,
    "if (cachedBlockingState.disabled || cachedBlockingState.paused)",
    "Cached rules must be suppressed while blocking is active"
)
assertContains(
    backgroundSource,
    "if (configuration.disabled === true || configuration.paused === true)",
    "Inert native configurations must not be applied or cached"
)
assertContains(
    backgroundSource,
    "state: \"error\", error: errorMessage",
    "Configuration lookup failures must reach content as an error state"
)
assertContains(
    backgroundSource,
    "text: blockingPaused ? \"II\" : \"\"",
    "Toolbar action should show a pause badge while blocking is paused"
)
assertContains(
    backgroundSource,
    "path: blockingPaused || siteDisabled ? DISABLED_ACTION_ICON : DEFAULT_ACTION_ICON",
    "Toolbar action should use disabled icon treatment while blocking is paused"
)
assertContains(
    popupSource,
    "const blockingPausedPromise = getBlockingPausedState();",
    "Popup should also reflect the global paused state shown in the toolbar"
)
assertContains(
    popupSource,
    "await browser.runtime.sendMessage({ action: 'wblock:clearCache' });",
    "Site setting changes must invalidate cached InitContentScript state"
)
assertContains(
    popupSource,
    "? t('popup_status_paused', undefined, 'Paused')",
    "Popup should show a paused status instead of active while globally paused"
)
assertContains(
    backgroundSource,
    "if (message && message.action === \"wblock:getBlockingState\")",
    "Legacy compatibility must route through one combined background state message"
)
assertContains(
    backgroundSource,
    "host: normalizedHost",
    "Combined compatibility state must include the normalized host"
)
assertContains(
    backgroundSource,
    "throw new Error(error)",
    "Missing native configuration must fail conservatively"
)
assertContains(
    contentSource,
    "action: \"wblock:getBlockingState\",",
    "Legacy content compatibility must use the combined state message"
)
assertNotContains(
    contentSource,
    "action: \"getBlockingPausedState\"",
    "Content compatibility must not send an unrouted pause action"
)

guard let reloadCoordinatorStart = contentBlockerService.range(of: "private actor ReloadCoordinator"),
      let reloadCoordinatorEnd = contentBlockerService.range(
        of: "private struct ReloadMarker",
        range: reloadCoordinatorStart.upperBound..<contentBlockerService.endIndex
      ) else {
    fputs("FAIL: missing ReloadCoordinator actor\n", stderr)
    exit(1)
}
let reloadCoordinator = String(
    contentBlockerService[reloadCoordinatorStart.lowerBound..<reloadCoordinatorEnd.lowerBound]
)
assertContains(
    contentBlockerService,
    "private actor ReloadCoordinator",
    "Reload coordination must serialize calls per target without a process-wide lock"
)
assertContains(
    contentBlockerService,
    "private static let reloadCoordinator = ReloadCoordinator()",
    "Reload coordination must be process-scoped"
)
assertContains(
    contentBlockerService,
    "await reloadCoordinator.withGate(key: identifier)",
    "Reload calls must acquire a gate keyed by target identifier"
)
assertContains(
    reloadCoordinator,
    "defer { release(key) }",
    "Every keyed reload gate must release on success, failure, and cancellation"
)
assertContains(
    reloadCoordinator,
    "private var activeKeys: Set<String> = []",
    "Reload gates must allow different target identifiers to run in parallel"
)
assertNotContains(
    reloadCoordinator,
    "Task.detached",
    "Keyed gate release must not race through a detached task"
)

assertContains(
    contentBlockerService,
    "public static let reloadCompletionTimeout: TimeInterval = 30",
    "Safari reload waits must stay bounded at 30 seconds"
)
assertContains(
    contentBlockerService,
    "public struct ReloadTimedOutError: LocalizedError, Sendable",
    "A dropped Safari completion must fail as ReloadTimedOutError"
)
assertContains(
    contentBlockerService,
    "private final class ResumeOnceGate: @unchecked Sendable",
    "Reload completion and the watchdog must share a resume-once gate"
)
guard let reloadStart = contentBlockerService.range(of: "public static func reloadContentBlocker("),
      let retryStart = contentBlockerService.range(
        of: "public static func reloadWithRetry(",
        range: reloadStart.upperBound..<contentBlockerService.endIndex
      ),
      let retryRawStart = contentBlockerService.range(
        of: "private static func reloadWithRetryRaw(",
        range: retryStart.upperBound..<contentBlockerService.endIndex
      ),
      let retryRawEnd = contentBlockerService.range(
        of: "public static func invalidateReloadMarker(",
        range: retryRawStart.upperBound..<contentBlockerService.endIndex
      ) else {
    fputs("FAIL: missing reload watchdog sections\n", stderr)
    exit(1)
}
let reloadContentBlocker = String(contentBlockerService[reloadStart.lowerBound..<retryStart.lowerBound])
let reloadRetry = String(contentBlockerService[retryRawStart.lowerBound..<retryRawEnd.lowerBound])
assertContains(
    reloadContentBlocker,
    "let gate = ResumeOnceGate()",
    "Reload must claim a resume-once gate before waiting on Safari"
)
assertContains(
    reloadContentBlocker,
    "guard gate.claim() else { return }",
    "Safari's completion handler must not resume after the watchdog"
)
assertContains(
    reloadContentBlocker,
    "Task.detached {",
    "The reload watchdog must stay detached so a stuck MainActor cannot starve the timeout"
)
assertContains(
    reloadContentBlocker,
    "try? await TaskSleep.sleep(for: .seconds(reloadCompletionTimeout))",
    "The watchdog must wait the documented reloadCompletionTimeout"
)
assertContains(
    reloadContentBlocker,
    "continuation.resume(returning: ReloadTimedOutError(identifier: identifier))",
    "The watchdog must fail the attempt as ReloadTimedOutError"
)
assertContains(
    reloadRetry,
    "if case .failure(let error) = result, error is ReloadTimedOutError {",
    "A timed-out reload must be recognized in the retry loop"
)
guard let timeoutCheck = reloadRetry.range(of: "error is ReloadTimedOutError"),
      let timeoutReturn = reloadRetry.range(
        of: "success: false",
        range: timeoutCheck.upperBound..<reloadRetry.endIndex
      ),
      let retryDelay = reloadRetry.range(of: "let delayMs = min(200 * attempt, 1500)") else {
    fputs("FAIL: timed-out reload must fail before the retry delay\n", stderr)
    exit(1)
}
if timeoutReturn.lowerBound > retryDelay.lowerBound {
    fputs("FAIL: timed-out reload must fail fast instead of retrying\n", stderr)
    exit(1)
}

print("PASS: blocking pause and reload coordination guardrails")
