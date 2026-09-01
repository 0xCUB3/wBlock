#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
func source(_ path: String) throws -> String { try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) }
func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let support = try source("wBlock/FilterCategorySupport.swift")
let content = try source("wBlock/ContentView.swift")
let info = try source("wBlock/FilterCategoryInfoView.swift")
require(support.contains("static func resetSelection"), "category reset must be a pure helper")
require(support.contains("guard filter.category == category else { return nil }"), "reset must scope to one category")
require(support.contains("return filter.isCustom ? false : defaultNames.contains(filter.name)"), "reset must disable custom filters and restore defaults")
require(content.contains("FilterCategoryInfoView("), "category headers must open the info sheet")
require(content.contains("FilterCategorySupport.defaultFilterNames"), "recommendations must come from authoritative defaults")
require(content.contains("filterManager.setFilterListSelection(id: filter.id, selected: selection)"), "non-foreign reset must use pending selection changes")
require(content.contains("if category == .foreign"), "regional reset must have separate recommendation behavior")
require(content.contains("onboardingSelectedLanguages"), "regional selection must reuse the onboarding defaults key")
require(content.contains("ForeignFilterOrganizer.recommendationBuckets(from: matching).recommended"), "regional selection must use recommended buckets")
require(content.contains("recommendedIDs.contains(filter.id) || !filter.isCustom"), "regional selection must preserve non-recommended custom lists")
require(content.contains("selected: recommendedIDs.contains(filter.id)"), "regional selection must enable recommendations and disable other non-custom lists")
require(info.contains("if category == .foreign"), "only Regional info must show the language selector")
require(info.contains("ForEach(availableLanguages"), "Regional info must list available foreign filter languages")
require(info.contains("onLanguagesChange(selectedLanguages)"), "language changes must apply regional recommendations")
require(info.contains("guard category == .foreign else { return defaultFilterNames }"), "other categories must keep catalog defaults")
require(info.contains("Recommended Filters"), "info must show recommended filters")
require(info.contains("Reset to Default"), "info must expose reset")
print("PASS")
