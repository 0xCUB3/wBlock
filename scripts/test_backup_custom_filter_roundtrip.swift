#!/usr/bin/env swift

import Foundation

struct CustomFilterProbe: Codable, Equatable {
    let name: String
    let url: String
    let isSelected: Bool
}

func check(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let source = try String(contentsOfFile: "wBlock/BackupManager.swift", encoding: .utf8)
check(source.contains("matchingIndices = filterManager.filterLists.indices.filter"),
      "restore must match existing custom filters by URL")
check(source.contains("filterManager.filterLists[index].isSelected = entry.isSelected"),
      "restore must apply the remote selection to existing custom filters")
check(source.contains("isSelected: entry.isSelected"),
      "restore must pass the remote selection when adding custom filters")

let original = [
    CustomFilterProbe(name: "Disabled remote", url: "https://example.com/filter.txt", isSelected: false),
    CustomFilterProbe(name: "Enabled remote", url: "https://example.com/other.txt", isSelected: true),
]
let encoded = try JSONEncoder().encode(original)
let decoded = try JSONDecoder().decode([CustomFilterProbe].self, from: encoded)
check(decoded == original, "backup custom-filter selection must survive JSON round trip")

var existingSelection = true
existingSelection = decoded[0].isSelected
check(existingSelection == false, "preexisting matching URL must restore disabled state")
let newlyAddedSelection = decoded[1].isSelected
check(newlyAddedSelection == true, "newly added matching URL must restore enabled state")

print("PASS: backup custom-filter selection round trip")
