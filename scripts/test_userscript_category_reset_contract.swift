#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let support = try source("wBlock/UserScriptCategorySupport.swift")
let info = try source("wBlock/UserScriptCategoryInfoView.swift")
let view = try source("wBlock/UserScriptManagerView.swift")
let manager = try source("wBlockCoreService/UserScriptManager.swift")
let onboarding = try source("wBlock/OnboardingView.swift")

require(support.contains("static func resetEnabled"), "category reset must be a pure helper")
require(support.contains("guard displayCategory == category else { return nil }"), "reset must scope to one display category")
require(support.contains("guard isBuiltIn else { return nil }"), "reset must leave custom scripts alone")
require(support.contains("return isEnabledByDefault"), "reset must restore built-in default enablement")
require(view.contains("UserScriptCategoryInfoView("), "category headers must open the info sheet")
require(view.contains("UserScriptCategorySupport.defaultScriptNames"), "recommendations must come from authoritative defaults")
require(view.contains("setEnabledScripts(withIDs: enabledIDs)"), "reset must apply the restored enablement set")
require(info.contains("Recommended Scripts"), "info must show recommended scripts")
require(info.contains("Reset to Default"), "info must expose reset")
require(manager.contains("isEnabledByDefaultByURL"), "built-in default enablement must be lookup data")
require(manager.contains("public func isEnabledByDefault"), "onboarding and reset must share one default-enablement API")
require(onboarding.contains("userScriptManager.isEnabledByDefault(script)"), "onboarding baseline must use built-in default enablement")
require(!onboarding.contains("localizedCaseInsensitiveCompare(\"AdGuard Extra\")"), "AdGuard Extra must not be hardcoded as an onboarding baseline")
require(!onboarding.contains("localizedCaseInsensitiveCompare(\"tinyShield\")"), "tinyShield must not be hardcoded as an onboarding baseline")
print("PASS")
