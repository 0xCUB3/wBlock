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
    "if BlockingPauseStore.isPaused() {\n                        message?[\"payload\"] = emptyRulesPayload()",
    "Advanced WebExtension lookups must return an empty payload while blocking is paused"
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
    "clearPersistedBlockingOutputsForPause()",
    "Auto-update should repair non-empty persisted outputs if it wakes during pause"
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
    "        } else {\n            await applyChanges()\n            await MainActor.run {",
    "Resuming blocking must use the standard visible apply pipeline"
)
assertNotContains(
    applyPipeline,
    "        } else {\n            await applyChanges(allowUserInteraction: true)\n            await MainActor.run {",
    "Resuming blocking must not suppress standard apply progress"
)
assertContains(
    appDelegate,
    "func applicationDidBecomeActive(_ application: UIApplication) {\n        guard !BlockingPauseStore.isPaused() else { return }\n\n        // Run opportunistic updates only when app is active (not during background launches).\n        Task {",
    "Foreground activation must skip opportunistic updates while blocking is paused"
)
assertContains(
    backgroundSource,
    "action: \"getBlockingPausedState\"",
    "Toolbar action state must query pause state from native storage"
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
    "? t('popup_status_paused', undefined, 'Paused')",
    "Popup should show a paused status instead of active while globally paused"
)

print("PASS: blocking pause guardrails")
