#!/usr/bin/env swift
import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

// #646: Apply must not re-check every userscript when they were verified
// inside the auto-update interval, matching the filter freshness window.
let manager = try read("wBlockCoreService/UserScriptManager.swift")
let pipeline = try read("wBlock/AppFilterManager+ApplyPipeline.swift")
let data = try read("wBlockCoreService/ProtobufDataManager.swift")
let proto = try read("wBlockCoreService/DataModels.proto")
let generated = try read("wBlockCoreService/DataModels.pb.swift")

require(proto.contains("map<string, int64> script_last_checked = 19;"), "proto field script_last_checked")
require(generated.contains("var scriptLastChecked: Dictionary<String,Int64>"), "generated scriptLastChecked accessor")
require(data.contains("mergeMap(&autoUpdate.scriptLastChecked, baseline: base.scriptLastChecked, persisted: theirs.scriptLastChecked)"), "merge rule for scriptLastChecked")
require(data.contains("public func getScriptLastChecked(_ uuid: String) -> Int64?") && data.contains("public func setScriptLastChecked(_ times: [String: Int64]) async"), "script last-checked accessors")

require(manager.contains("static func scriptsRequiringNetworkCheck("), "planner helper exists")
require(manager.contains("skipFresh: Bool = false,"), "autoUpdateEnabledUserScripts keeps a non-skipping default for background runs")
require(manager.contains("verifiedTimes[candidate.id.uuidString] = now") && manager.contains("await ProtobufDataManager.shared.setScriptLastChecked(verifiedTimes)"), "successful checks are recorded per script")

let applyCall = pipeline.range(of: "userScriptManager.autoUpdateEnabledUserScripts(").map { pipeline[$0.upperBound...].prefix(80) } ?? ""
require(applyCall.contains("skipFresh: true"), "Apply pipeline skips fresh scripts")

// Planner behavior, mirrored from the production helper body.
struct Script { let id: UUID }
func plan(_ scripts: [Script], lastChecked: (UUID) -> Date?, interval: TimeInterval, now: Date) -> [Script] {
    scripts.filter { script in
        guard let checked = lastChecked(script.id) else { return true }
        return now.timeIntervalSince(checked) >= interval
    }
}
let fresh = Script(id: UUID()), stale = Script(id: UUID()), never = Script(id: UUID())
let now = Date()
let times: [UUID: Date] = [fresh.id: now.addingTimeInterval(-600), stale.id: now.addingTimeInterval(-7 * 3600)]
let due = plan([fresh, stale, never], lastChecked: { times[$0] }, interval: 6 * 3600, now: now).map(\.id)
require(due == [stale.id, never.id], "only stale or never-checked scripts are due")
require(manager.contains("guard let checked = lastChecked(script.id) else { return true }\n            return now.timeIntervalSince(checked) >= interval"), "production planner matches mirrored body")

print("PASS test_issue_646_script_freshness")
