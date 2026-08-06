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
    "BlockingPauseStore.isPaused(groupIdentifier: groupIdentifier)",
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
    "var targetsToReload: [ContentBlockerTargetInfo] = []",
    "Pause clearing should write every blocker target before reload failures can abort the pass"
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
    "await MainActor.run { self.isBlockingPaused = false }\n            await applyChanges()\n            await MainActor.run {",
    "Resuming blocking must use the standard visible apply pipeline"
)
assertNotContains(
    applyPipeline,
    "        } else {\n            await applyChanges(allowUserInteraction: true)\n            await MainActor.run {",
    "Resuming blocking must not suppress standard apply progress"
)
assertContains(
    appDelegate,
    "func applicationWillBecomeActive(_ notification: Notification) {\n        guard !BlockingPauseStore.isPaused() else { return }\n\n        // Check if update is overdue when app becomes active\n        Task {",
    "macOS foreground activation must skip opportunistic updates while blocking is paused"
)
assertContains(
    appDelegate,
    "func applicationDidBecomeActive(_ application: UIApplication) {\n        guard !BlockingPauseStore.isPaused() else { return }\n\n        // Run opportunistic updates only when app is active (not during background launches).\n        Task {",
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

print("PASS: blocking pause guardrails")
