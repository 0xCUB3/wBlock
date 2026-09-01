#!/usr/bin/env swift

import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func slice(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start) else {
        fputs("FAIL: missing \(start)\n", stderr)
        exit(1)
    }
    guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
        fputs("FAIL: missing \(end) after \(start)\n", stderr)
        exit(1)
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let pipeline = try String(contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift", encoding: .utf8)
let manager = try String(contentsOfFile: "wBlock/AppFilterManager.swift", encoding: .utf8)
let progressView = try String(contentsOfFile: "wBlock/ApplyChangesProgressView.swift", encoding: .utf8)

let cancelInFlight = slice(pipeline, from: "func cancelInFlightApply()", to: "private func unwindApplyAfterUserCancel")
require(
    cancelInFlight.contains("ApplyCancellation.cancel(userInitiated: true)"),
    "cancelInFlightApply must mark cancellation as user-initiated"
)
require(
    cancelInFlight.contains("exclusiveApplyTask?.cancel()"),
    "cancelInFlightApply must cancel the exclusive apply task"
)

let failIfCancelled = slice(pipeline, from: "private func failApplyIfCancelled()", to: "// MARK: - Delegated methods")
require(
    failIfCancelled.contains("ApplyCancellation.isUserInitiated") &&
        failIfCancelled.contains("await unwindApplyAfterUserCancel()"),
    "failApplyIfCancelled must unwind on user-initiated cancel"
)
let userCancelBranch = slice(
    pipeline,
    from: "if ApplyCancellation.isUserInitiated {",
    to: "#if os(iOS)"
)
require(
    !userCancelBranch.contains("markFailed") && !userCancelBranch.contains("failApplyRun"),
    "user-initiated cancel must not mark the apply failed"
)

let unwind = slice(pipeline, from: "private func unwindApplyAfterUserCancel()", to: "private func failApplyIfCancelled")
require(
    unwind.contains("showingApplyProgressSheet = false"),
    "user cancel must dismiss the apply progress sheet"
)
require(
    !unwind.contains("persistFailedUpgradeRebuildSignature"),
    "user cancel must not persist a failed upgrade rebuild signature"
)
require(
    !unwind.contains("markFailed"),
    "user cancel must not mark the progress view model failed"
)

require(
    manager.contains("var exclusiveApplyTask: Task<Void, Never>?"),
    "AppFilterManager must store the exclusive apply task for cancellation"
)

let exclusive = slice(pipeline, from: "func performExclusiveApply", to: "func applyChanges(")
require(
    exclusive.contains("ApplyCancellation.cancel()"),
    "iOS suspension shield must cooperatively cancel apply"
)
require(
    !exclusive.contains("ApplyCancellation.cancel(userInitiated: true)"),
    "suspension shield must not treat expiration as user cancel"
)

let progressToolbar = progressView.components(separatedBy: "private var progressToolbar").dropFirst().first?
    .components(separatedBy: "private var reviewToolbar").first ?? ""
require(
    progressToolbar.contains("String(localized: \"Cancel\")") &&
        progressToolbar.contains("cancelInFlightApply()"),
    "apply progress sheet must offer Cancel that stops the in-flight apply"
)

print("PASS: apply user cancel contract")
