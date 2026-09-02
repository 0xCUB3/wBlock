#!/usr/bin/env swift
import Foundation

// Regression contract for GitHub issue #621 ("more log details").
// The app log must explain failures, not just count them:
//  - every failed content blocker reload carries the Safari error
//  - thrown errors are logged through LogErrorDescriber, never localizedDescription
//  - warnings and errors record their source file:line
//  - entries survive a relaunch and the export names the app/OS/device

func check(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

func read(_ path: String) -> String {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        fputs("FAIL: cannot read \(path)\n", stderr); exit(1)
    }
    return text
}

func section(_ source: String, from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
    else { fputs("FAIL: missing source section: \(start)\n", stderr); exit(1) }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let core = read("wBlockCoreService/wBlockCoreService.swift")
let describer = read("wBlockCoreService/LogErrorDescriber.swift")
let manager = read("wBlock/ConcurrentLogManager.swift")
let pipeline = read("wBlock/AppFilterManager+ApplyPipeline.swift")
let disabledSites = read("wBlock/AppFilterManager+DisabledSites.swift")
let appDelegate = read("wBlock/AppDelegate.swift")

// 1. Reload failures carry a reason on every failure exit.
let resultType = section(core, from: "public struct ReloadAttemptResult", to: "private actor ReloadCoordinator")
check(resultType.contains("public let failureReason: String?"), "ReloadAttemptResult must expose failureReason")
check(resultType.contains("failureReason: String? = nil"), "failureReason must default to nil for success paths")

let reloadCode = section(core, from: "public static func reloadIfNeeded(", to: "public static func invalidateReloadMarker(")
var scan = reloadCode.startIndex
var failureConstructors = 0
var missingReason = 0
while let range = reloadCode.range(of: "ReloadAttemptResult(", range: scan..<reloadCode.endIndex) {
    let tail = reloadCode[range.upperBound...]
    guard let close = tail.range(of: "\n        }") ?? tail.range(of: ")\n") else { break }
    let body = String(tail[..<close.lowerBound])
    if body.contains("success: false") {
        failureConstructors += 1
        if !body.contains("failureReason:") { missingReason += 1 }
    }
    scan = range.upperBound
}
check(failureConstructors >= 12, "expected to scan the reload failure exits, found \(failureConstructors)")
check(missingReason == 0, "\(missingReason) reload failure exit(s) return no failureReason")
check(reloadCode.contains("lastFailureReason = LogErrorDescriber.describe(error)"), "retry loop must keep the last Safari error")

// 2. The apply pipeline logs one entry per failed blocker with the reason.
let reloadPhase = section(pipeline, from: "func reloadContentBlockers(_ targets:", to: "static func allowProgressUIRefresh()")
check(reloadPhase.contains("Failed to reload content blocker"), "apply reload phase must log each failed blocker")
check(reloadPhase.contains("\"error\": result.reload.failureReason ?? \"unknown\""), "per-blocker entry must carry failureReason")
check(reloadPhase.contains("\"bundleId\": result.target.bundleIdentifier"), "per-blocker entry must carry bundleId")
check(disabledSites.contains("\"error\": result.failureReason ?? \"unknown\""), "fast disabled-sites reload must log failureReason")
check(disabledSites.contains("Failed to update disabled sites for blocker"), "fast disabled-sites update must log per-blocker write errors")

// 3. removeparam DNR failures are no longer swallowed by try?.
check(!pipeline.contains("try? RemoveParamDNRRuleGenerator.saveRules("), "removeparam DNR save must not use try?")
check(pipeline.contains("Failed to prepare removeparam DNR rules\"),\n                error: error"), "removeparam DNR warning must include the thrown error")

// 4. Errors are described consistently.
check(describer.contains("public enum LogErrorDescriber"), "LogErrorDescriber must be public")
check(describer.contains("NSUnderlyingErrorKey"), "describer must follow the underlying error chain")
let appSources = [
    "wBlock/AppFilterManager.swift", "wBlock/AppFilterManager+ApplyPipeline.swift",
    "wBlock/AppFilterManager+CustomFilters.swift", "wBlock/AppFilterManager+DisabledSites.swift",
    "wBlock/FilterListUpdater.swift", "wBlock/FilterListLoader.swift",
    "wBlock/UserScriptManagerView.swift", "wBlock/LogsView.swift",
]
for path in appSources {
    let text = read(path)
    check(!text.contains("\"error\": error.localizedDescription"), "\(path) logs error.localizedDescription")
    check(!text.contains("\"error\": \"\\(error)\""), "\(path) logs raw error interpolation")
}

// 5. Log manager: source stamp, persistence, environment.
check(manager.contains("if level >= .warning, resolvedMetadata[\"source\"] == nil"), "warnings and errors must record source file:line")
check(manager.contains("func loadPersistedEntriesIfNeeded()"), "log manager must load persisted entries")
check(manager.contains("func persistNow()"), "log manager must expose persistNow")
check(manager.contains("appendingPathComponent(\"logs.json\")"), "log manager must persist to logs.json")
check(manager.contains("removePersistedEntries()"), "clearLogs must delete the persisted file")
check(manager.contains("func logLaunch()"), "log manager must record launches")
for key in ["App: \\(environment[\"app\"]", "OS: \\(environment[\"os\"]", "Device: \\(environment[\"device\"]"] {
    check(manager.contains(key), "export header must include \(key)")
}
check(appDelegate.components(separatedBy: "ConcurrentLogManager.shared.logLaunch()").count == 3, "both platform delegates must call logLaunch")
check(appDelegate.components(separatedBy: "ConcurrentLogManager.shared.persistNow()").count >= 3, "both platform delegates must flush logs on terminate")

// 6. New strings are localized everywhere.
let fm = FileManager.default
let lprojs = (try? fm.contentsOfDirectory(atPath: "wBlock"))?.filter { $0.hasSuffix(".lproj") } ?? []
check(lprojs.count >= 17, "expected at least 17 lproj folders, found \(lprojs.count)")
for lproj in lprojs {
    let strings = read("wBlock/\(lproj)/Localizable.strings")
    for key in ["wBlock launched", "Failed to reload content blocker", "Failed to update disabled sites for blocker"] {
        check(strings.contains("\"\(key)\" = \""), "\(lproj) is missing \"\(key)\"")
    }
}

print("PASS: log detail contract (issue #621)")
