#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}
func require(_ text: String, _ needle: String, _ message: String) {
    guard text.contains(needle) else {
        fputs("FAIL: \(message)\nMissing: \(needle)\n", stderr)
        exit(1)
    }
}

let customFiltersSource = try source("wBlock/AppFilterManager+CustomFilters.swift")
require(
    customFiltersSource,
    "removeCustomFilterList(newFilterToAdd, recordDeletion: false)",
    "Failed custom filter download must remove without poisoning CloudSync deletion tombstones"
)
require(
    customFiltersSource,
    "filterLists.removeAll { $0.id == filter.id || ($0.isCustom && $0.url == filter.url) }",
    "Removing a custom filter must remove all matching instances by ID or URL"
)
require(
    customFiltersSource,
    "if !filterLists.contains(where: { $0.url == filter.url })",
    "addCustomFilterList must check for duplicate URLs across all filter lists"
)

let appFilterManagerSource = try source("wBlock/AppFilterManager.swift")
require(
    appFilterManagerSource,
    "if let index = result.firstIndex(where: { $0.url == filter.url }) {",
    "collapseDuplicateBuiltInURLs must collapse duplicate URLs across all lists"
)

print("PASS: custom filter duplicate and cleanup contract")
