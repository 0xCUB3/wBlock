#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
func check(_ condition: Bool, _ message: String) { guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) } }

let onboarding = try source("wBlock/OnboardingView.swift")
check(onboarding.contains(".interactiveDismissDisabled(!hasCompletedOnboarding)"), "incomplete onboarding must not be dismissible")
let completion = onboarding.range(of: "setHasCompletedOnboarding(true)")!.lowerBound
let dismissal = onboarding.range(of: "dismiss()", range: completion..<onboarding.endIndex)!.lowerBound
check(completion < dismissal, "completion must be persisted before dismissal")
print("PASS")
