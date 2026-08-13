#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let grouping = try source("wBlock/FilterListGrouping.swift")
let content = try source("wBlock/ContentView.swift")
require(grouping.contains("[\"18\", \"19\", \"20\", \"21\", \"22\"]"), "registry IDs 18–22 must be authoritative")
require(grouping.contains("!filter.isCustom, filter.category == .annoyances"), "grouping must not absorb custom filters")
require(grouping.contains("static func groups(for filters: [FilterList])"), "grouping must be a pure helper")
require(content.contains("FilterListGrouping.groups(for: item.filters)"), "iOS must render through grouping helper")
require(content.contains("FilterListGrouping.groups(for: filters)"), "macOS must render through grouping helper")
require(content.contains("@AppStorage(\"adGuardAnnoyancesExpanded\") private var isAdGuardAnnoyancesExpanded = true"), "group must default expanded")
require(content.contains("|| !filterSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty"), "search matches must force group expansion")
require(content.contains("Text(LocalizedStringKey(group.title ?? \"\"))"), "group title must be rendered")
let macOSGrouping = content.components(separatedBy: "private func macOSFilterSectionView").last?
    .components(separatedBy: "private func macOSForeignFiltersView").first ?? ""
require(!macOSGrouping.contains("DisclosureGroup(isExpanded: adGuardAnnoyancesExpansion)"), "macOS must not use the awkward edge-aligned system disclosure")
require(macOSGrouping.contains("Image(systemName: \"chevron.right\")"), "macOS group header needs a trailing disclosure indicator")
require(macOSGrouping.contains(".buttonStyle(.plain)"), "macOS group header must remain visually integrated with the card")
require(macOSGrouping.contains("if adGuardAnnoyancesExpansion.wrappedValue"), "macOS group header must control child visibility")
print("PASS")
