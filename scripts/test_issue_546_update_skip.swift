#!/usr/bin/env swift
import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

func requiresFullApply(
    hasUnappliedChanges: Bool,
    missingFilterCount: Int,
    missingScriptCount: Int
) -> Bool {
    hasUnappliedChanges || missingFilterCount > 0 || missingScriptCount > 0
}

func extractFunctionBody(_ source: String, signature: String) -> String {
    guard let start = source.range(of: signature) else {
        fputs("FAIL: missing \(signature)\n", stderr)
        exit(1)
    }
    let after = source[start.lowerBound...]
    let searchFrom = after.index(after: start.upperBound)
    let nextFunc = after.range(
        of: "\n    func ",
        range: searchFrom..<after.endIndex
    ) ?? after.range(
        of: "\n    static func ",
        range: searchFrom..<after.endIndex
    )
    return nextFunc.map { String(after[..<$0.lowerBound]) } ?? String(after)
}

let repoRoot = FileManager.default.currentDirectoryPath
func read(_ relative: String) throws -> String {
    try String(contentsOfFile: "\(repoRoot)/\(relative)", encoding: .utf8)
}

let manager = try read("wBlock/AppFilterManager.swift")
let settings = try read("wBlock/SettingsView.swift")
let content = try read("wBlock/ContentView.swift")
let onboarding = try read("wBlock/OnboardingView.swift")

let exactExpr = "hasUnappliedChanges || missingFilterCount > 0 || missingScriptCount > 0"
check(
    manager.contains(exactExpr),
    "AppFilterManager.swift must contain exact requiresFullApply expression"
)

check(
    requiresFullApply(hasUnappliedChanges: false, missingFilterCount: 0, missingScriptCount: 0) == false,
    "all-false → false"
)
for (u, f, s) in [
    (true, 0, 0),
    (false, 1, 0),
    (false, 0, 1),
    (true, 2, 3),
    (false, 5, 0),
] {
    check(
        requiresFullApply(hasUnappliedChanges: u, missingFilterCount: f, missingScriptCount: s),
        "any true input → true (u=\(u) f=\(f) s=\(s))"
    )
}

check(manager.contains("func applyOrCheckForUpdates()"), "applyOrCheckForUpdates must exist")
check(manager.contains("Self.requiresFullApply("), "applyOrCheckForUpdates must call requiresFullApply")

let applyBody = extractFunctionBody(manager, signature: "func applyOrCheckForUpdates()")
check(applyBody.contains("waitUntilReady()"), "applyOrCheckForUpdates must await waitUntilReady()")
check(
    applyBody.contains("UserScriptManager.shared.waitUntilReady()"),
    "applyOrCheckForUpdates must await UserScriptManager.shared.waitUntilReady()"
)
check(
    applyBody.contains("filterUpdater.userScriptManager == nil"),
    "applyOrCheckForUpdates must nil-guard userScriptManager before setUserScriptManager"
)
check(
    applyBody.contains("setUserScriptManager(UserScriptManager.shared)"),
    "applyOrCheckForUpdates must setUserScriptManager when nil"
)
check(applyBody.contains("refreshMissingItems()"), "applyOrCheckForUpdates must refresh missing items")
check(applyBody.contains("performFilterUpdate()"), "applyOrCheckForUpdates must reference performFilterUpdate")
check(applyBody.contains("checkForUpdates()"), "applyOrCheckForUpdates must reference checkForUpdates")

guard let taskRange = applyBody.range(of: "Task {") else {
    fputs("FAIL: applyOrCheckForUpdates missing Task {\n", stderr)
    exit(1)
}
let beforeTask = applyBody[..<taskRange.lowerBound]
check(
    beforeTask.contains("isLoading = true"),
    "applyOrCheckForUpdates must set isLoading = true synchronously before Task {"
)
check(
    applyBody.contains("let started = await self.performFilterUpdate()"),
    "applyOrCheckForUpdates must capture performFilterUpdate started result"
)
check(
    applyBody.contains("if !started {") && applyBody.contains("self.isLoading = false"),
    "applyOrCheckForUpdates must clear isLoading when performFilterUpdate did not start"
)

if let ifRange = applyBody.range(of: "if Self.requiresFullApply") {
    let afterIf = applyBody[ifRange.lowerBound...]
    guard let elseRange = afterIf.range(of: "} else {") else {
        fputs("FAIL: applyOrCheckForUpdates missing else branch\n", stderr)
        exit(1)
    }
    let trueBranch = String(afterIf[..<elseRange.lowerBound])
    let falseBranch = String(afterIf[elseRange.upperBound...])
    check(trueBranch.contains("performFilterUpdate()"), "performFilterUpdate must be in true branch")
    check(!trueBranch.contains("checkForUpdates()"), "checkForUpdates must not be in true branch")
    check(falseBranch.contains("checkForUpdates()"), "checkForUpdates must be in else branch")
    check(!falseBranch.contains("performFilterUpdate()"), "performFilterUpdate must not be in else branch")
} else {
    fputs("FAIL: applyOrCheckForUpdates missing requiresFullApply guard\n", stderr)
    exit(1)
}

check(manager.contains("func forceApplyChanges()"), "forceApplyChanges must exist")
let forceBody = extractFunctionBody(manager, signature: "func forceApplyChanges()")
check(forceBody.contains("guard !isLoading, !isApplyInFlight else { return }"), "forceApplyChanges must guard against in-flight apply/loading")
check(forceBody.contains("waitUntilReady()"), "forceApplyChanges must await waitUntilReady()")
check(
    forceBody.contains("UserScriptManager.shared.waitUntilReady()"),
    "forceApplyChanges must await UserScriptManager.shared.waitUntilReady()"
)
check(
    forceBody.contains("filterUpdater.userScriptManager == nil"),
    "forceApplyChanges must nil-guard userScriptManager before setUserScriptManager"
)
check(
    forceBody.contains("setUserScriptManager(UserScriptManager.shared)"),
    "forceApplyChanges must setUserScriptManager when nil"
)
check(forceBody.contains("refreshMissingItems()"), "forceApplyChanges must refresh missing items")
check(forceBody.contains("performFilterUpdate()"), "forceApplyChanges must reference performFilterUpdate")
check(!forceBody.contains("checkForUpdates()"), "forceApplyChanges must never reference checkForUpdates")

guard let forceTaskRange = forceBody.range(of: "Task {") else {
    fputs("FAIL: forceApplyChanges missing Task {\n", stderr)
    exit(1)
}
let forceBeforeTask = forceBody[..<forceTaskRange.lowerBound]
check(
    forceBeforeTask.contains("isLoading = true"),
    "forceApplyChanges must set isLoading = true synchronously before Task {"
)
check(
    forceBody.contains("let started = await self.performFilterUpdate()"),
    "forceApplyChanges must capture performFilterUpdate started result"
)
check(
    forceBody.contains("if !started {") && forceBody.contains("self.isLoading = false"),
    "forceApplyChanges must clear isLoading when performFilterUpdate did not start"
)

check(
    manager.contains("self.checkAndEnableFilters(forceReload: true)"),
    "AppFilterManager debounce must still call checkAndEnableFilters(forceReload: true)"
)

let updateNowCalls = settings.components(separatedBy: "filterManager.applyOrCheckForUpdates()").count - 1
check(updateNowCalls >= 2, "SettingsView Update Now → applyOrCheckForUpdates (found \(updateNowCalls))")
check(
    !settings.contains("checkAndEnableFilters(forceReload: true)"),
    "SettingsView must not call checkAndEnableFilters(forceReload: true)"
)

let applyPendingBody = extractFunctionBody(content, signature: "private func applyPendingChanges()")
check(
    applyPendingBody.contains("applyOrCheckForUpdates()"),
    "ContentView applyPendingChanges → applyOrCheckForUpdates()"
)
check(
    !applyPendingBody.contains("checkAndEnableFilters(forceReload: true)"),
    "ContentView applyPendingChanges must not force-reload"
)

let externalBody = extractFunctionBody(content, signature: "private func applyFilterChangesFromExternalTrigger()")
check(
    externalBody.contains("checkAndEnableFilters(forceReload: true)"),
    "applyFilterChangesFromExternalTrigger must still force-reload"
)

let onboardingForceCount = onboarding.components(separatedBy: "checkAndEnableFilters(forceReload: true)").count - 1
check(onboardingForceCount >= 2, "OnboardingView force-reload twice")

print("PASS: issue 546 manager and view contract")
