#!/usr/bin/env swift

import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let pipeline = try String(contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift", encoding: .utf8)
let progressView = try String(contentsOfFile: "wBlock/ApplyChangesProgressView.swift", encoding: .utf8)

func slice(from startNeedle: String, to endNeedle: String?) -> String {
    guard let start = pipeline.range(of: startNeedle) else {
        fputs("FAIL: missing \(startNeedle)\n", stderr)
        exit(1)
    }
    if let endNeedle, let end = pipeline.range(of: endNeedle, range: start.upperBound..<pipeline.endIndex) {
        return String(pipeline[start.lowerBound..<end.lowerBound])
    }
    return String(pipeline[start.lowerBound...])
}

// Closing the app mid-apply leaves kernel flocks on app-group files (engine
// publish, protobuf, filter writes). iOS then kills the process with
// 0xDEAD10CC. Combined-engine publish already has its own shield; the manual
// apply session needs a matching assertion for the rest of the run, plus a
// cooperative cancel so locks drop instead of dying.
let exclusive = slice(from: "func performExclusiveApply", to: "func applyChanges(")
require(exclusive.contains("#if os(iOS)"),
        "the apply shield must be iOS-only")
require(exclusive.contains("#else"),
        "macOS must keep the unshielded await work() path")
require(exclusive.contains("await work()"),
        "macOS must still run the exclusive work")
require(exclusive.contains("ApplySuspensionShield") && pipeline.contains("performExpiringActivity"),
        "performExclusiveApply must install performExpiringActivity")
require(
    exclusive.contains("beginBackgroundTask") || exclusive.contains("ApplyBackgroundTaskHandle"),
    "performExclusiveApply must install beginBackgroundTask"
)
require(pipeline.contains("beginBackgroundTask"),
        "the iOS shield must call UIApplication.beginBackgroundTask")
require(exclusive.contains("defer { shield.release() }"),
        "the expiring-activity assertion must lapse when apply unwinds")
require(exclusive.contains("backgroundTask.end()") || exclusive.contains("endBackgroundTask"),
        "the background task must be ended on the same unwind path")
require(exclusive.contains("ApplyCancellation.cancel()") || exclusive.contains("applyTask.cancel()"),
        "imminent suspension must mark the apply cancelled")
require(!exclusive.contains("completion.wait()"),
        "performExclusiveApply must not block the MainActor on the activity semaphore")
require(pipeline.contains("DispatchQueue.global"),
        "the activity wait must start off the MainActor")

let refresh = slice(from: "func allowProgressUIRefresh", to: nil)
require(
    refresh.contains("isCancelled") && refresh.contains("checkCancellation"),
    "allowProgressUIRefresh must observe expiration/cancellation"
)
require(pipeline.contains("failApplyIfCancelled") && pipeline.contains("failApplyRun"),
        "cancellation must fail the run cleanly instead of aborting mid-write")

// Conversion still takes app-group locks (removeparam DNR writes, per-target
// compile). Those must observe the cooperative cancel flag before starting.
let beforeRemoveParam = slice(
    from: "let disabledSites = runSnapshot.disabledSites",
    to: "RemoveParamDNRRuleGenerator.saveRules"
)
require(
    beforeRemoveParam.contains("failApplyIfCancelled"),
    "must cancel-check before RemoveParamDNRRuleGenerator.saveRules"
)
let beforeCompile = slice(
    from: "operation: { work in",
    to: "ContentBlockerService.compileTargetRules"
)
require(
    beforeCompile.contains("isCancelled"),
    "must cancel-check before compileTargetRules"
)
let conversionOperation = slice(
    from: "operation: { work in",
    to: "onResult: { completion in"
)
let cancellationCatch = slice(
    from: "catch is CancellationError",
    to: "} catch {"
)
require(
    cancellationCatch.contains("failureDescription: nil") &&
        !cancellationCatch.contains("ApplyCancellation.cancel()"),
    "a target CancellationError must not invent a suspension cancellation"
)
let missingOutcomeHandling = slice(
    from: "if let missingOutcomeTarget",
    to: "if let failedTarget"
)
require(
    missingOutcomeHandling.contains("failApplyIfCancelled()") &&
        missingOutcomeHandling.contains("Failed to convert rules for blocker") &&
        !missingOutcomeHandling.contains("Missing conversion result for blocker"),
    "missing conversion outcomes must use suspension cancellation only when it was requested"
)

require(
    progressView.contains("case .failed:") &&
        progressView.contains("String(localized: \"Try Again\")") &&
        progressView.contains("filterManager.forceApplyChanges()") &&
        progressView.contains("filterManager.isLoading || filterManager.isApplyInFlight"),
    "the failed apply sheet must offer a disabled-while-running force-apply retry"
)

print("PASS: apply suspension shield and retry contract")
