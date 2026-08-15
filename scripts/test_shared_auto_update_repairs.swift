#!/usr/bin/env swift

import Foundation

func read(_ path: String) throws -> String { try String(contentsOfFile: path, encoding: .utf8) }
func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let manager = try read("wBlockCoreService/SharedAutoUpdateManager.swift")
let lease = try read("wBlockCoreService/SharedAutoUpdateLease.swift")
let utils = try read("wBlockCoreService/Utils.swift")
let service = try read("wBlockCoreService/wBlockCoreService.swift")

require(lease.contains("flock") && lease.contains("LOCK_EX | LOCK_NB"), "run ownership must use a kernel flock")
require(lease.contains("deinit") && lease.contains("LOCK_UN"), "the lease must release on process teardown")
require(manager.contains("withExtendedLifetime(lease)"), "every early return must retain the lease until run exit")
require(manager.contains("SharedAutoUpdateLease.acquire"), "every started run must acquire the shared lease")
require(!manager.contains("heartbeatTask") && !manager.contains("runningFlagStalenessThreshold"), "run ownership must not use a wall-clock heartbeat")
require(manager.contains("rebuildAndReload(\n                            selectedFilters: []"), "empty selections must rebuild through the normal pipeline")
require(manager.contains("let hasPersistedOutput = contentBlockerOutputsContainRules()"), "clean first runs must be distinguished from stale output")
require(utils.contains("hasCoherentBaseRulesCache"), "incremental cache must validate all sidecars")
require(service.contains("hasCoherentBaseRulesCache"), "conversion must reject incomplete incremental caches")
require(utils.contains("filter-\\(filter.id.uuidString).txt"), "malformed non-custom names need an ID-based filename")
require(service.contains("advancedRulesText: advancedRulesText.isEmpty ? nil : advancedRulesText"), "fast cache hits must retain advanced rules")
print("PASS: shared auto-update lease, empty-selection, cache, and path-safety contracts")
