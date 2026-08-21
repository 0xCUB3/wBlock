#!/usr/bin/env swift
import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func section(_ source: String, _ start: String, _ end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source[startRange.lowerBound...].range(of: end) else {
        require(false, "missing section '\(start)' .. '\(end)'")
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.upperBound])
}

let updates = try read("wBlock/AppFilterManager+Updates.swift")
let content = try read("wBlock/ContentView.swift")
let userScriptView = try read("wBlock/UserScriptManagerView.swift")
let filterManager = try read("wBlock/AppFilterManager.swift")

// 1) UpdateCheckScope cases and default .all
let scopeEnum = section(updates, "enum UpdateCheckScope", "case all")
require(scopeEnum.contains("case filters") && scopeEnum.contains("case scripts") && scopeEnum.contains("case all"), "UpdateCheckScope cases")
let checkSig = section(updates, "func checkForUpdates(scope: UpdateCheckScope = .all)", "async {")
require(checkSig.contains("scope: UpdateCheckScope = .all"), "checkForUpdates default .all")

// 2) scoped switch branches
let sw = section(updates, "switch scope {", "let totalUpdates")
let filtersCase = section(sw, "case .filters:", "case .scripts:")
require(filtersCase.contains("await checkEnabledFilterUpdates()") && filtersCase.contains("availableScriptUpdates = []") && !filtersCase.contains("checkUserScriptUpdates"), "filters case")
let scriptsCase = section(sw, "case .scripts:", "case .all:")
require(scriptsCase.contains("availableUpdates = []") && scriptsCase.contains("await checkUserScriptUpdates()") && !scriptsCase.contains("checkEnabledFilterUpdates"), "scripts case")
let allCase = section(sw, "case .all:", "}")
require(allCase.contains("await checkEnabledFilterUpdates()") && allCase.contains("await checkUserScriptUpdates()"), "all case")

// 3) checkUserScriptUpdates readiness, fallback attachment, and reading order
let scriptCheck = section(updates, "private func checkUserScriptUpdates() async", "func downloadAndApplySelectedUpdates")
require(scriptCheck.contains("filterUpdater.userScriptManager ?? UserScriptManager.shared"), "resolves shared fallback")
require(scriptCheck.contains("if filterUpdater.userScriptManager == nil") && scriptCheck.contains("setUserScriptManager(userScriptManager)"), "attaches fallback when nil")
guard let readyRange = scriptCheck.range(of: "await userScriptManager.waitUntilReady()"),
      let scriptsRange = scriptCheck.range(of: "userScriptManager.userScripts") else {
    require(false, "missing readiness or userScripts read in checkUserScriptUpdates")
    exit(1)
}
require(readyRange.upperBound <= scriptsRange.lowerBound, "waitUntilReady must run before reading userScripts")

// 4) ContentView filter .refreshable uses .filters & UserScriptManagerView uses .scripts
let filterRefresh = section(content, ".refreshable", "await filterManager.checkForUpdates(scope: .filters)")
require(filterRefresh.contains("checkForUpdates(scope: .filters)"), "filter refresh uses .filters")
let scriptInit = section(content, "UserScriptManagerView(", "await filterManager.checkForUpdates(scope: .scripts)")
require(scriptInit.contains("onRefresh:") && scriptInit.contains("checkForUpdates(scope: .scripts)"), "UserScriptManagerView uses .scripts")

// 5) UserScriptManagerView declares async onRefresh and iOS list awaits it in .refreshable
let usDecl = section(userScriptView, "struct UserScriptManagerView", "let onRefresh: () async -> Void")
require(usDecl.contains("let onRefresh: () async -> Void"), "UserScriptManagerView declares async onRefresh")
let usContent = section(userScriptView, "private var userScriptContent", "await onRefresh()")
let usRefresh = section(usContent, "#if os(iOS)", "await onRefresh()")
require(usRefresh.contains(".refreshable") && usRefresh.contains("await onRefresh()"), "iOS list awaits onRefresh in .refreshable")

// 6) global AppFilterManager path still awaits checkForUpdates() with default all
let applyOrCheck = section(filterManager, "func applyOrCheckForUpdates()", "await self.checkForUpdates()")
require(applyOrCheck.contains("await self.checkForUpdates()"), "applyOrCheckForUpdates calls checkForUpdates() default all")

print("PASS: scoped update check contract")
