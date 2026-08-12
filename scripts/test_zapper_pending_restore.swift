#!/usr/bin/env swift

import Foundation

struct ZapperRuleList: Codable, Equatable {
    var selectors: [String] = []
    var pendingDeletions: [String] = []

    mutating func delete(_ selector: String) {
        selectors.removeAll { $0 == selector }
        pendingDeletions.append(selector)
    }

    mutating func restore(_ selector: String, at index: Int) {
        pendingDeletions.removeAll { $0 == selector }
        selectors.insert(selector, at: min(max(index, 0), selectors.count))
    }

    mutating func consumePendingDeletions() -> Set<String> {
        let deletions = Set(pendingDeletions)
        pendingDeletions.removeAll()
        return deletions
    }
}

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

let managerSource = try String(
    contentsOfFile: "wBlockCoreService/ProtobufDataManager.swift",
    encoding: .utf8
)
guard managerSource.contains("ruleList.pendingDeletions.removeAll { $0 == selector }") else {
    fail("restoreZapperRule must clear a matching pending deletion")
}

var rules = ZapperRuleList(selectors: [".ad", ".promo"])
rules.delete(".ad")
guard rules == ZapperRuleList(selectors: [".promo"], pendingDeletions: [".ad"]) else {
    fail("deletion must retain a pending deletion marker")
}

rules.restore(".ad", at: 0)
let serialized = try JSONEncoder().encode(rules)
let reloaded = try JSONDecoder().decode(ZapperRuleList.self, from: serialized)
guard reloaded == ZapperRuleList(selectors: [".ad", ".promo"], pendingDeletions: []) else {
    fail("restore must serialize the restored selector without a deletion marker")
}

var syncState = reloaded
let deletionSet = syncState.consumePendingDeletions()
let extensionRules = [".ad", ".promo", ".new"].filter { !deletionSet.contains($0) }
syncState.selectors = extensionRules

guard extensionRules == [".ad", ".promo", ".new"], syncState.pendingDeletions.isEmpty else {
    fail("the next extension sync must retain the restored selector")
}

print("PASS: zapper pending deletion restore survives serialization and sync")
