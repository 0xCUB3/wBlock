#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
func require(_ text: String, _ needle: String) {
    guard text.contains(needle) else { fputs("FAIL: missing \(needle)\n", stderr); exit(1) }
}
let content = try source("wBlock/ContentView.swift")
require(content, "OnboardingPresentationModifier")
require(content, "UIDevice.current.userInterfaceIdiom == .pad")
require(content, ".fullScreenCover(isPresented: $isPresented)")
require(content, ".sheet(isPresented: $isPresented)")
require(content, ".onChangeCompat(of: selectedTab)")
require(content, "pendingEssentialFilter")
require(content, "filterRequirementsPanel")
let scripts = try source("wBlock/UserScriptManagerView.swift")
require(scripts, "showingPasteReplacementConfirmation")
require(scripts, "Replace Existing Content?")
require(scripts, "if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty")
require(scripts, "requirementsPanel")
let localization = try source("wBlock/LocalizationHelpers.swift")
require(localization, "NSLocalizedString(\"Other\"")
let settings = try source("wBlock/SettingsView.swift")
require(settings, "private var advancedSection")
require(settings, "private var helpSection")
require(settings, "Report Issues")
let zapper = try source("wBlock/SiteSettingsView.swift")
require(zapper, "Clear Element Zapper Rules?")
require(zapper, "ruleManager.deleteAllRules()")
print("PASS")
