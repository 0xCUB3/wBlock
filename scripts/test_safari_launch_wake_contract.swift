#!/usr/bin/env swift
import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func section(_ source: String, _ start: String, _ end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source[startRange.lowerBound...].range(of: end) else {
        require(false, "missing section '\(start)' .. '\(end)'")
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.upperBound])
}

let availability = try read("wBlockCoreService/SafariProcessAvailability.swift")
require(availability.contains("public enum SafariProcessAvailability"), "SafariProcessAvailability must be public")
require(
    availability.contains("com.apple.Safari") && availability.contains("com.apple.SafariTechnologyPreview"),
    "must check Safari and Safari Technology Preview bundle IDs"
)
require(availability.contains("!$0.isTerminated"), "must treat terminated Safari instances as not running")

let userScriptManager = try read("wBlockCoreService/UserScriptManager.swift")
let invalidate = section(
    userScriptManager,
    "public static func invalidateDocumentStartExecutionCache() {",
    "SFSafariApplication.dispatchMessage("
)
require(
    invalidate.contains("SafariProcessAvailability.isSafariOrTechnologyPreviewRunning"),
    "userscript cache invalidation must gate on Safari running"
)
require(
    invalidate.contains("Skipped Safari userscript cache invalidation"),
    "userscript skip must be logged"
)

let zapper = try read("wBlock/ZapperRuleManager.swift")
let notify = section(zapper, "static func notifySafariRulesChanged() {", "SFSafariApplication.dispatchMessage(")
require(
    notify.contains("SafariProcessAvailability.isSafariOrTechnologyPreviewRunning"),
    "zapper rules refresh must gate on Safari running"
)
require(notify.contains("Skipped Safari zapper rules refresh"), "zapper skip must be logged")

let contentBlockerService = try read("wBlockCoreService/wBlockCoreService.swift")
guard let reloadStart = contentBlockerService.range(of: "public static func reloadContentBlocker("),
      let retryStart = contentBlockerService.range(
        of: "public static func reloadWithRetry(",
        range: reloadStart.upperBound..<contentBlockerService.endIndex
      ) else {
    require(false, "missing reloadContentBlocker")
    exit(1)
}
let reloadFn = String(contentBlockerService[reloadStart.lowerBound..<retryStart.lowerBound])
// Safari only recompiles a content blocker when it is asked to reload; it does
// not re-read the rules file on launch. SFContentBlockerManager queues the
// request without opening Safari, so the reload must never be skipped because
// Safari is closed (3.0.0 did, and Safari kept serving stale rules).
require(
    !reloadFn.contains("SafariProcessAvailability.isSafariOrTechnologyPreviewRunning"),
    "content blocker reload must not gate on Safari running"
)
require(
    reloadFn.contains("SFContentBlockerManager.reloadContentBlocker"),
    "content blocker reload must call SFContentBlockerManager.reloadContentBlocker"
)

let appDelegate = try read("wBlock/AppDelegate.swift")
let didFinishLaunching = section(
    appDelegate,
    "func applicationDidFinishLaunching(_ notification: Notification) {",
    "setupMacOSAutoUpdate()"
)
require(
    didFinishLaunching.contains("UserScriptManager.invalidateDocumentStartExecutionCache()"),
    "launch must still request userscript cache invalidation; the Safari running guard no-ops it"
)

print("OK: safari launch wake contract")
