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
