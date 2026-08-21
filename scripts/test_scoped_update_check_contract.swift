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

func occurrences(_ source: String, _ value: String) -> Int {
    source.components(separatedBy: value).count - 1
}

let updates = try read("wBlock/AppFilterManager+Updates.swift")
let content = try read("wBlock/ContentView.swift")
let userScriptView = try read("wBlock/UserScriptManagerView.swift")
let filterManager = try read("wBlock/AppFilterManager.swift")

// 1) UpdateCheckScope cases and blocking presentation default
let scopeEnum = section(updates, "enum UpdateCheckScope", "case all")
require(scopeEnum.contains("case filters") && scopeEnum.contains("case scripts") && scopeEnum.contains("case all"), "UpdateCheckScope cases")
let presentationEnum = section(updates, "enum UpdateCheckPresentation", "case refresh")
require(presentationEnum.contains("case blocking") && presentationEnum.contains("case refresh"), "UpdateCheckPresentation cases")
let checkSig = section(updates, "func checkForUpdates(", ") async {")
require(checkSig.contains("scope: UpdateCheckScope = .all") && checkSig.contains("presentation: UpdateCheckPresentation = .blocking"), "checkForUpdates defaults")

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

// 4) Both presentations load; only refresh suppresses the blocking overlay.
let updateCheck = section(updates, "func checkForUpdates(", "private func checkEnabledFilterUpdates")
let lifecycle = "if presentation == .refresh {\n            suppressBlockingOverlay = true\n        }\n        isLoading = true\n        defer {\n            isLoading = false\n            if presentation == .refresh {\n                suppressBlockingOverlay = false\n            }\n        }"
require(updateCheck.contains(lifecycle) && occurrences(updateCheck, "isLoading =") == 2 && occurrences(updateCheck, "suppressBlockingOverlay =") == 2, "refresh suppresses only the blocking overlay while both paths load")
require(updateCheck.contains("if presentation == .blocking {\n                showingNoUpdatesAlert = true\n            }") && occurrences(updateCheck, "showingNoUpdatesAlert = true") == 1, "blocking empty path presents no-updates alert")

// 5) ContentView refresh call sites use refresh presentation.
let filterRefresh = section(content, ".refreshable", "await filterManager.checkForUpdates(scope: .filters, presentation: .refresh)")
require(filterRefresh.contains("checkForUpdates(scope: .filters, presentation: .refresh)"), "filter refresh presentation")
let scriptInit = section(content, "UserScriptManagerView(", "await filterManager.checkForUpdates(scope: .scripts, presentation: .refresh)")
require(scriptInit.contains("onRefresh:") && scriptInit.contains("checkForUpdates(scope: .scripts, presentation: .refresh)"), "script refresh presentation")

// 6) UserScriptManagerView declares async onRefresh and iOS list awaits it in .refreshable
let usDecl = section(userScriptView, "struct UserScriptManagerView", "let onRefresh: () async -> Void")
require(usDecl.contains("let onRefresh: () async -> Void"), "UserScriptManagerView declares async onRefresh")
let usContent = section(userScriptView, "private var userScriptContent", "await onRefresh()")
let usRefresh = section(usContent, "#if os(iOS)", "await onRefresh()")
require(usRefresh.contains(".refreshable") && usRefresh.contains("await onRefresh()"), "iOS list awaits onRefresh in .refreshable")

// 7) global AppFilterManager path still awaits checkForUpdates() with default all
let applyOrCheck = section(filterManager, "func applyOrCheckForUpdates()", "await self.checkForUpdates()")
require(applyOrCheck.contains("await self.checkForUpdates()"), "applyOrCheckForUpdates calls checkForUpdates() default all")

print("PASS: scoped update check contract")
