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
let dataManager = try read("wBlockCoreService/ProtobufDataManager.swift")

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
