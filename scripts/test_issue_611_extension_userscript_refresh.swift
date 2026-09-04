#!/usr/bin/env swift
import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func read(_ path: String) throws -> String { try String(contentsOfFile: path, encoding: .utf8) }

// #611: userscripts refresh from the Safari extension while browsing, filters do not.
let handler = try read("wBlockCoreService/WebExtensionRequestHandler.swift")
let source = try read("extension-src/background.js")
let bundled = try read("wBlock Scripts (iOS)/Resources/background.js")

require(handler.contains("case \"maybeUpdateUserScripts\":"), "native action registered")
let body = handler.components(separatedBy: "private static func handleMaybeUpdateUserScripts")[1]
    .components(separatedBy: "private static func handleGetFilterUpdateStatus")[0]
require(body.contains("ProtobufDataManager.shared.autoUpdateEnabled"), "respects the auto-update switch")
require(body.contains("BlockingPauseStore.isPaused(.userScripts)"), "respects the userscripts pause")
require(body.contains("autoUpdateEnabledUserScripts(skipFresh: true)"), "skips scripts checked inside the interval")
require(!body.contains("maybeRunAutoUpdate") && !body.contains("refreshFiltersIfNeeded"), "never runs the filter pipeline from the extension")
require(body.contains("userScriptRefreshQueue.begin()") && body.contains("userScriptRefreshQueue.finish()"), "serializes overlapping pings")

require(source.contains("sendQueuedNativeMessage({ action: \"maybeUpdateUserScripts\" })"), "extension sends the ping")
require(source.contains("USERSCRIPT_REFRESH_PING_INTERVAL_MS = 15 * 60 * 1000"), "ping throttle is 15 minutes")
require(source.contains("if (changeInfo && changeInfo.status === \"complete\") {\n          maybeRefreshUserScripts();"), "ping fires after page completion")
require(bundled.contains("maybeUpdateUserScripts"), "minified bundle carries the action")
print("PASS test_issue_611_extension_userscript_refresh")
