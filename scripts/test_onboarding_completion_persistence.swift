#!/usr/bin/env swift

import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let onboarding = try read("wBlock/OnboardingView.swift")
let filterManager = try read("wBlock/AppFilterManager.swift")
let dataManager = try read("wBlockCoreService/ProtobufDataManager.swift")
let settings = try read("wBlock/SettingsView.swift")
let app = try read("wBlock/wBlockApp.swift")

require(
    onboarding.contains("@State private var selectedBlockingLevel: String"),
    "blocking level must be a local onboarding draft"
)
require(
    onboarding.contains("selectedBlockingLevel = level.rawValue")
        && !onboarding.contains("setSelectedBlockingLevel(level.rawValue)"),
    "blocking level selection must not persist immediately"
)
require(
    onboarding.contains("await dataManager.setSelectedBlockingLevel(selectedBlockingLevel)")
        && onboarding.contains("sharedDefaults.set(Array(selectedLanguages), forKey: Self.selectedLanguagesDefaultsKey)"),
    "blocking level and languages must persist during applySettings"
)
require(
    !onboarding.contains("sharedDefaults.set(Array(newValue), forKey: Self.selectedLanguagesDefaultsKey)"),
    "language changes must remain local drafts"
)
let resetStart = filterManager.range(of: "func completeResetForOnboarding() async")!.lowerBound
let resetEnd = filterManager.range(
    of: "func resetOnboardingUserDefaults()",
    range: resetStart..<filterManager.endIndex
)!.lowerBound
let resetFlow = String(filterManager[resetStart..<resetEnd])
let preservingReset = resetFlow.range(of: "resetToDefaultData(preservingOnboardingCompletion: true)")!.lowerBound
let filterReset = resetFlow.range(of: "await resetForOnboarding()")!.lowerBound
let userscriptReset = resetFlow.range(of: "await UserScriptManager.shared.simulateFreshInstall()")!.lowerBound
let scheduleReset = resetFlow.range(of: "await SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()")!.lowerBound
let presentationTrigger = resetFlow.range(of: "setHasCompletedOnboarding(false)")!.lowerBound
require(
    preservingReset < filterReset
        && filterReset < userscriptReset
        && userscriptReset < scheduleReset
        && scheduleReset < presentationTrigger,
    "complete restart must preserve completion through intermediate resets and clear it last"
)
require(
    settings.contains("await filterManager.completeResetForOnboarding()")
        && app.contains("await filterManager.completeResetForOnboarding()"),
    "Danger Zone and macOS menu must use the complete restart path"
)

require(
    filterManager.contains("@MainActor\n    func resetForOnboarding() async"),
    "onboarding reset UI mutations must remain on MainActor"
)
require(
    filterManager.contains("let groupIdentifier = GroupIdentifier.shared.value\n        do {\n            try await Task.detached {\n                try ContentBlockerService.publishCombinedFilterEngine("),
    "onboarding reset must publish the synchronous engine off the main actor"
)
require(
    !filterManager.contains("groupIdentifier: GroupIdentifier.shared.value"),
    "the detached onboarding publish must capture the Sendable group identifier first"
)
require(
    !onboarding.contains("private func setHasCompletedOnboarding"),
    "onboarding completion must not use a fire-and-forget wrapper"
)
require(
    onboarding.components(separatedBy: "guard await dataManager.setHasCompletedOnboarding(true) else { return }").count == 3,
    "both onboarding completion paths must await a successful completion write"
)
require(
    dataManager.contains("guard await saveDataImmediately() else { return false }\n        return await updateDataImmediately { $0.settings.hasCompletedOnboarding_p = value }"),
    "pending setup state and the completion marker must be persisted before dismissal"
)

print("PASS: onboarding completion persistence")
