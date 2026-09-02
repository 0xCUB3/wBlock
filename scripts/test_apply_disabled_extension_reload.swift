#!/usr/bin/env swift
import Foundation

// Regression contract: an extension the user turned off in Safari settings must
// not fail the apply run. Before this contract, every apply failed once Safari
// refused those reloads, the failed upgrade signature was persisted, and the
// Apply button stayed pending across launches with nothing left to apply.

func check(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let core = try String(contentsOfFile: "wBlockCoreService/wBlockCoreService.swift", encoding: .utf8)
let pipeline = try String(contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift", encoding: .utf8)
let strings = try String(contentsOfFile: "wBlock/en.lproj/Localizable.strings", encoding: .utf8)

func section(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
    else { fputs("FAIL: missing source section: \(start)\n", stderr); exit(1) }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let resultType = section(core, from: "public struct ReloadAttemptResult", to: "private actor ReloadCoordinator")
check(resultType.contains("public let disabledInSafari: Bool"), "ReloadAttemptResult must expose disabledInSafari")
check(resultType.contains("disabledInSafari: Bool = false"), "disabledInSafari must default to false for existing callers")

let serial = section(core, from: "private static func reloadIfNeededSerially(", to: "public static func reloadContentBlocker(")
check(
    serial.contains("let enabledInSafari = await contentBlockerIsEnabled(identifier: identifier)"),
    "reloadIfNeededSerially must query Safari's enabled state before reloading"
)
check(
    serial.contains("maxRetries: enabledInSafari ? maxRetries : 1"),
    "a disabled extension must get a single reload attempt instead of the full retry ladder"
)
check(
    serial.contains("disabledInSafari: !enabledInSafari"),
    "a failed reload of a disabled extension must be reported as disabledInSafari"
)
if let enabledCheck = serial.range(of: "let enabledInSafari = await contentBlockerIsEnabled"),
   let reloadCall = serial.range(of: "let reload = await reloadWithRetryRaw(") {
    check(enabledCheck.lowerBound < reloadCall.lowerBound, "enabled state must be read before the reload attempt")
}

let reloadPhase = section(pipeline, from: "func reloadContentBlockers(_ targets: [ContentBlockerTargetInfo])", to: "static func allowProgressUIRefresh()")
check(
    reloadPhase.contains("allSuccessful = allSuccessful && (result.reload.success || result.reload.disabledInSafari)"),
    "reload phase must treat disabled-in-Safari targets as non-fatal"
)
check(
    reloadPhase.contains("if result.reload.disabledInSafari {") && reloadPhase.contains("disabledInSafariNames.append(name)"),
    "disabled targets must be collected separately from failed targets"
)
check(
    reloadPhase.contains("} else if !result.reload.success {") && reloadPhase.contains("failedNames.append(name)"),
    "only genuine reload failures may populate failedNames and set hasError"
)
check(
    reloadPhase.contains("disabledInSafariNames: disabledInSafariNames"),
    "ReloadPhaseSummary must carry the disabled target names"
)

check(
    pipeline.contains("let failedReloads = activeReloads.filter { !$0.success && !$0.disabledInSafari }"),
    "reload metrics must not count disabled extensions as failures"
)
check(
    pipeline.contains("if !reloadSummary.disabledInSafariNames.isEmpty {"),
    "a successful apply must still surface extensions that are turned off in Safari"
)
check(
    pipeline.contains("allReloadsSuccessful && advancedEngineSucceeded && !self.hasError"),
    "apply success must keep depending on the reload summary"
)

let warningKey = "%@ turned off in Safari. Enable them in Safari settings to load the applied rules."
check(strings.contains("\"\(warningKey)\" = "), "English strings must define the disabled-in-Safari warning")

print("PASS: disabled Safari extensions do not fail apply")
