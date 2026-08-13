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
let aggregateDisclosure = content.components(separatedBy: "private func adGuardAnnoyancesDisclosure").last?
    .components(separatedBy: "private func categoryHeader").first ?? ""
require(aggregateDisclosure.contains("DisclosureGroup(isExpanded: adGuardAnnoyancesExpansion)"), "iOS aggregate row must retain native disclosure behavior")
require(aggregateDisclosure.contains("group.sourceRuleCount"), "aggregate row must show the sum of child rules")
require(aggregateDisclosure.contains("Toggle(\"\", isOn: adGuardAnnoyancesSelection(ids: ids))"), "aggregate row needs an all-child switch")
require(aggregateDisclosure.contains(".toggleStyle(.switch)"), "aggregate row must use the same switch style as child filters")
let macDisclosure = aggregateDisclosure.components(separatedBy: "#if os(macOS)").last?
    .components(separatedBy: "#else").first ?? ""
require(macDisclosure.contains("HStack(alignment: .center, spacing: 10)"), "macOS aggregate must match ordinary row geometry")
require(macDisclosure.contains(".padding(16)"), "macOS aggregate must use the same inset as ordinary rows")
require(macDisclosure.contains("? \"chevron.down\"\n                                : \"chevron.right\""), "macOS trailing chevron must reflect expansion state")
require(macDisclosure.contains("adGuardAnnoyancesToggle(ids: ids, title: group.title)"), "macOS switch must remain in the standard trailing-control position")
require(macDisclosure.contains("if adGuardAnnoyancesExpansion.wrappedValue {\n                Divider()"), "expanded children must render directly below the aggregate row")
require(!macDisclosure.contains("VStack(alignment: .leading, spacing: 0) {\n                adGuardAnnoyancesSummary"), "child rows must not have a disclosure-only horizontal offset")
require(aggregateDisclosure.contains("Blocks cookie notices, popups, mobile app banners, widgets, and other annoyances."), "aggregate row needs a description")
require(content.contains("filterManager.filterLists.contains { ids.contains($0.id) && $0.isSelected }"), "aggregate switch must read live manager state")
require(content.components(separatedBy: "adGuardAnnoyancesDisclosure(group)").count == 3, "iOS and macOS must share the native disclosure")
require(manager.contains("func setFilterListSelections(ids: Set<UUID>, selected: Bool)"), "aggregate switch must batch child selection")
require(grouping.contains("counts.reduce(0, +)"), "aggregate rules must sum child counts")
print("PASS")
