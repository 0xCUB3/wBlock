#!/usr/bin/env swift

import Foundation

let manager = try String(contentsOfFile: "wBlock/AppFilterManager.swift", encoding: .utf8)
let content = try String(contentsOfFile: "wBlock/ContentView.swift", encoding: .utf8)
let updater = try String(contentsOfFile: "wBlock/FilterListUpdater.swift", encoding: .utf8)

guard manager.contains("guard totalRules >= totalCapacity else { return }") else {
    fputs("FAIL: rule-limit warning can still appear below aggregate capacity\n", stderr)
    exit(1)
}
guard !content.contains("filter.limitExceededReason") else {
    fputs("FAIL: filter rows still invoke or render per-filter rule-limit warnings\n", stderr)
    exit(1)
}
guard updater.contains("let eligibleFilters = filterLists") else {
    fputs("FAIL: stale persisted per-filter limit reasons still suppress updates\n", stderr)
    exit(1)
}
print("PASS")
