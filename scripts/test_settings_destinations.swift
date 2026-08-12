#!/usr/bin/env swift

import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func assertContains(_ text: String, _ needle: String, _ message: String) {
    guard text.contains(needle) else {
        fputs("FAIL: \(message)\nMissing: \(needle)\n", stderr)
        exit(1)
    }
}

func assertNotContains(_ text: String, _ needle: String, _ message: String) {
    guard !text.contains(needle) else {
        fputs("FAIL: \(message)\nUnexpected: \(needle)\n", stderr)
        exit(1)
    }
}

let settings = try read("wBlock/SettingsView.swift")
let site = try read("wBlock/SiteSettingsView.swift")
let zapper = try read("wBlock/ElementZapperSettingsView.swift")

assertContains(settings, "SiteSettingsView()", "Settings must expose a separate Site Settings destination")
assertContains(settings, "ElementZapperSettingsView(filterManager: filterManager)", "Settings must expose a separate Element Zapper destination")
assertContains(site, ".navigationTitle(\"Site Settings\")", "Site Settings must retain its own title")
assertContains(site, "Reset Site Settings", "Site Settings must retain reset")
assertContains(site, "pendingUndo", "Site Settings must retain undo state")
assertContains(site, "setWhitelistedDomains", "Site Settings must retain per-domain blocking settings")
assertContains(site, "setUserScriptDisabledHosts", "Site Settings must retain per-domain userscript settings")
assertNotContains(site, "ZapperRuleManager", "Site Settings must not own zapper data")
assertNotContains(site, "Clear Element Zapper Rules", "Site Settings must not own global zapper clearing")
assertContains(zapper, ".navigationTitle(\"Element Zapper\")", "Element Zapper must have its own title")
assertContains(zapper, "Clear Element Zapper Rules", "Element Zapper must own global clearing")
assertContains(zapper, "setZapperRulesDisabled(!enabled, forHost: domain)", "Element Zapper must expose per-domain rule toggles")
assertContains(zapper, "Changes take full effect after the next apply.", "Zapper apply guidance must be its own line")
assertContains(zapper, "ruleManager.rules(for: domain)", "Element Zapper must render per-domain rules")

print("PASS: split settings destination structure")
