#!/usr/bin/env swift
import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

func slice(_ source: String, from startNeedle: String, to endNeedle: String) -> String {
    guard let start = source.range(of: startNeedle) else {
        fputs("FAIL: missing \(startNeedle)\n", stderr)
        exit(1)
    }
    guard let end = source.range(of: endNeedle, range: start.upperBound..<source.endIndex) else {
        fputs("FAIL: missing \(endNeedle) after \(startNeedle)\n", stderr)
        exit(1)
    }
    return String(source[start.lowerBound..<end.lowerBound])
}

let manager = try String(contentsOfFile: "wBlock/AppFilterManager.swift", encoding: .utf8)
let pipeline = try String(contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift", encoding: .utf8)

let exclusive = slice(pipeline, from: "func performExclusiveApply", to: "func applyChanges(")
let successGuardPattern = #"if\s+lastApplySucceeded\s+&&\s+hasUnappliedChanges[\s\S]*?scheduleAutoApplyDebounce\(\)"#
let successGuard = try NSRegularExpression(pattern: successGuardPattern)
check(
    successGuard.firstMatch(in: exclusive, range: NSRange(exclusive.startIndex..., in: exclusive)) != nil,
    "performExclusiveApply must only schedule its unwind debounce after a successful apply"
)

let failure = slice(pipeline, from: "private func failApplyRun", to: "private func failApplyIfCancelled")
check(failure.contains("autoApplyTask?.cancel()"), "failApplyRun must cancel autoApplyTask")
check(failure.contains("autoApplyTask = nil"), "failApplyRun must clear autoApplyTask")
check(
    failure.contains("persistFailedUpgradeRebuildSignature()"),
    "failApplyRun must persist the failed upgrade signature"
)

let persistCalls = pipeline.components(separatedBy: "persistUpgradeRebuildSignature()").count - 1
let clearAfterPersistPattern = #"persistUpgradeRebuildSignature\(\)\s+self\.clearFailedUpgradeRebuildSignature\(\)"#
let clearAfterPersist = try NSRegularExpression(pattern: clearAfterPersistPattern)
let clearAfterPersistCalls = clearAfterPersist.matches(
    in: pipeline,
    range: NSRange(pipeline.startIndex..., in: pipeline)
).count
check(persistCalls > 0, "ApplyPipeline must persist successful upgrade rebuild signatures")
check(
    clearAfterPersistCalls == persistCalls,
    "every successful upgrade-signature persist site must clear the failed signature"
)

let forceApply = slice(manager, from: "func forceApplyChanges()", to: "func toggleFilterListSelection")
check(
    forceApply.contains("clearFailedUpgradeRebuildSignature()"),
    "forceApplyChanges must clear the failed signature before retrying"
)

let setup = slice(manager, from: "func setup()", to: "private func collapseDuplicateBuiltInURLs")
check(setup.contains("if needsRebuild"), "setup must retain the rebuild-pending branch")
check(
    setup.contains("markNonSelectionChangesPending()"),
    "setup must keep failed rebuild changes pending for manual Apply"
)
check(
    setup.contains("storedFailedUpgradeSignature() == currentSignature"),
    "setup must recognize a failure for the current upgrade signature"
)
check(
    setup.contains("autoApplyTask?.cancel()") && setup.contains("autoApplyTask = nil"),
    "setup must suppress relaunch auto-apply after a failed upgrade attempt"
)

print("PASS: apply failure auto-retry suppression")
