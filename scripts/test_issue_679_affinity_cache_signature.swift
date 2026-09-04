#!/usr/bin/env swift
// Source contract for #679: the per-target conversion cache must stay usable
// when affinity lists are present, and its signature must cover everything
// that feeds a target: assigned lists, replicated affinity contributors, and
// per-list excluded sites.
import Foundation

func read(_ path: String) -> String {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("FAIL: could not read \(path)")
        exit(1)
    }
    return text
}

func require(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
        exit(1)
    }
}

let core = read("wBlockCoreService/wBlockCoreService.swift")
let utils = read("wBlockCoreService/Utils.swift")

guard let start = core.range(of: "public static func compileTargetRules(\n        filters: [FilterList],\n        orderedSelectedFilters: [FilterList],\n        affinitySnapshot:") else {
    print("FAIL: compileTargetRules(affinitySnapshot:) not found")
    exit(1)
}
let tail = core[start.upperBound...]
let body = tail[..<(tail.range(of: "/// Compatibility overload")?.lowerBound ?? tail.endIndex)]

require(!body.contains("hasAffinityFilters\n            ? nil"), "affinity mode must not disable the input signature")
require(!body.contains("invalidateInputSignature("), "affinity mode must not invalidate the stored signature on every run")
require(body.contains("affinityContributors: affinityContributors"), "signature must receive the replicated affinity contributors")
require(body.contains("affinitySnapshot.content(for: $0.id) != nil"), "contributors are the unassigned lists present in the affinity snapshot")

require(utils.contains("affinityContributors: [FilterList] = []"), "computeInputSignature must accept affinity contributors")
require(utils.contains("excludedSitesMarker(for: filter)"), "signature must include per-list excluded sites")
require(utils.contains("inputSignatureSchemaVersion = \"5\""), "schema version must bump so stale signatures do not suppress a needed rebuild")

print("PASS")
