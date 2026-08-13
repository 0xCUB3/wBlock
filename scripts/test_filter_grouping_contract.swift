#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let grouping = try source("wBlock/FilterListGrouping.swift")
let content = try source("wBlock/ContentView.swift")
let manager = try source("wBlock/AppFilterManager.swift")
require(grouping.contains("[\"18\", \"19\", \"20\", \"21\", \"22\"]"), "registry IDs 18–22 must be authoritative")
require(grouping.contains("!filter.isCustom, filter.category == .annoyances"), "grouping must not absorb custom filters")
require(grouping.contains("static func groups(for filters: [FilterList])"), "grouping must be a pure helper")
require(content.contains("FilterListGrouping.groups(for: item.filters)"), "iOS must render through grouping helper")
require(content.contains("FilterListGrouping.groups(for: filters)"), "macOS must render through grouping helper")
require(content.contains("@AppStorage(\"adGuardAnnoyancesExpanded\") private var isAdGuardAnnoyancesExpanded = true"), "group must default expanded")
require(content.contains("|| !filterSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty"), "search matches must force group expansion")
require(content.contains("Text(LocalizedStringKey(group.title ?? \"\"))"), "group title must be rendered")
let aggregateHeader = content.components(separatedBy: "private func adGuardAnnoyancesHeader").last?
    .components(separatedBy: "private func categoryHeader").first ?? ""
require(aggregateHeader.contains("group.sourceRuleCount"), "aggregate row must show the sum of child rules")
require(aggregateHeader.contains("Image(systemName: \"chevron.right\")"), "aggregate row needs a disclosure indicator")
require(aggregateHeader.contains("Toggle(\"\", isOn: adGuardAnnoyancesSelection(group))"), "aggregate row needs an all-child switch")
require(aggregateHeader.contains(".toggleStyle(.switch)"), "aggregate row must use the same switch style as child filters")
require(aggregateHeader.contains("Blocks cookie notices, popups, mobile app banners, widgets, and other annoyances."), "aggregate row needs a description")
let titleRange = aggregateHeader.range(of: "Text(LocalizedStringKey(group.title")
let chevronRange = aggregateHeader.range(of: "Image(systemName: \"chevron.right\")")
let countRange = aggregateHeader.range(of: "if let count = group.sourceRuleCount")
require(titleRange != nil && chevronRange != nil && countRange != nil && titleRange!.lowerBound < chevronRange!.lowerBound && chevronRange!.lowerBound < countRange!.lowerBound, "disclosure indicator must sit beside the title")
require(content.contains("group.filters.contains(where: \\.isSelected)"), "aggregate switch must stay on while any child is selected")
require(manager.contains("func setFilterListSelections(ids: Set<UUID>, selected: Bool)"), "aggregate switch must batch child selection")
require(grouping.contains("counts.reduce(0, +)"), "aggregate rules must sum child counts")
print("PASS")
