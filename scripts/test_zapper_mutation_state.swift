#!/usr/bin/env swift
import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

struct Undo {
    let rule: String
    let originalIndex: Int
    let previous: String?
    let next: String?
    let version: Int
}

func restoreIndex(_ rules: [String], _ undo: Undo, version: Int) -> Int? {
    guard undo.version == version, !rules.contains(undo.rule) else { return nil }
    if let next = undo.next, let index = rules.firstIndex(of: next) { return index }
    if let previous = undo.previous, let index = rules.firstIndex(of: previous) { return index + 1 }
    return min(max(undo.originalIndex, 0), rules.count)
}

var rules = [".first", ".deleted", ".last"]
let undo = Undo(rule: ".deleted", originalIndex: 1, previous: ".first", next: ".last", version: 1)
rules.remove(at: 1)
check(restoreIndex(rules, undo, version: 1) == 1, "undo should use the surviving neighbor anchor")
rules.insert(".new", at: 1)
check(restoreIndex(rules, undo, version: 2) == nil, "undo must be invalid after an intervening mutation")
check(restoreIndex(rules, undo, version: 1) == 2, "validated anchor should preserve order after an intervening insertion")

let view = try String(contentsOfFile: "wBlock/ElementZapperSettingsView.swift", encoding: .utf8)
let manager = try String(contentsOfFile: "wBlock/ZapperRuleManager.swift", encoding: .utf8)
for needle in ["mutationVersion", "previousRule", "nextRule", "beginMutation", "undo.version == mutationVersion", "isMutating || ruleManager.isMutationInFlight"] {
    check(view.contains(needle), "zapper view is missing mutation safety: \(needle)")
}
for needle in ["mutationTail", "performMutation", "isMutationInFlight"] {
    check(manager.contains(needle), "zapper manager is missing serialization: \(needle)")
}
print("PASS")
