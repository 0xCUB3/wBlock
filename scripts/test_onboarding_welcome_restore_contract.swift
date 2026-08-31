#!/usr/bin/env swift
import Foundation

let source = try String(contentsOfFile: "wBlock/OnboardingView.swift", encoding: .utf8)

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let footerStart = source.range(of: "private var onboardingFooter")!.lowerBound
let footerEnd = source.range(of: "private var footerButtonDisabled", range: footerStart..<source.endIndex)!.lowerBound
let footer = String(source[footerStart..<footerEnd])
require(
    footer.contains("if step == .welcome")
        && footer.contains("Button(String(localized: \"Restore from backup…\"))")
        && footer.contains("showingBackupImporter = true"),
    "the welcome footer must present the existing restore-from-backup importer"
)

let restoreStart = source.range(of: "private func performBackupRestore() async")!.lowerBound
let restore = String(source[restoreStart..<source.endIndex])
let backupCall = restore.range(of: "await BackupManager.restoreBackup(backup, filterManager: filterManager)")!.lowerBound
let setupComplete = restore.range(of: "userScriptManager.markInitialSetupComplete()")!.lowerBound
let completion = restore.range(of: "guard await dataManager.setHasCompletedOnboarding(true) else { return }")!.lowerBound
let dismissal = restore.range(of: "dismiss()")!.lowerBound
let filterApply = restore.range(of: "filterManager.checkAndEnableFilters(forceReload: true)")!.lowerBound
require(
    backupCall < setupComplete
        && setupComplete < completion
        && completion < dismissal
        && dismissal < filterApply,
    "a successful restore must persist onboarding completion before dismissal and filter apply"
)

print("PASS: onboarding welcome restore contract")
