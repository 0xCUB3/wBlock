#!/usr/bin/env swift
import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func section(_ source: String, _ start: String, _ end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source[startRange.lowerBound...].range(of: end) else {
        require(false, "missing section '\(start)' .. '\(end)'")
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.upperBound])
}

let updater = try read("wBlock/FilterListUpdater.swift")
let updates = try read("wBlock/AppFilterManager+Updates.swift")

require(updater.contains("pendingDownloads.removeAll()"), "a new check must drop stale checked downloads")
require(updater.contains("pendingDownloads.store"), "detected updates must keep the checked payload")
require(updater.contains("pendingDownloads.take"), "apply must reuse the checked payload instead of downloading again")

let check = section(updater, "func checkForUpdates(filterLists:", "return filtersWithUpdates")
require(check.contains("await pendingDownloads.removeAll()"), "checkForUpdates clears leftover payloads first")

let hasUpdate = section(updater, "private func hasUpdateNoMainActor(", "case .unchangedContent:")
require(
    hasUpdate.contains("case .updatedContent:")
        && hasUpdate.contains("pendingDownloads.store")
        && hasUpdate.contains("CachedFilterDownload(from: result)"),
    "updatedContent must cache the fetched body"
)

let fetch = section(updater, "private func fetchAndProcessFilterResult(", "func processDownloadedFilter(")
require(
    fetch.contains("pendingDownloads.take(filter.id)")
        && fetch.contains("processDownloadedFilter(filter, download: cached)"),
    "fetch must consume the checked payload before another GET"
)
require(
    fetch.contains("FilterListFetchChain.fetch")
        && fetch.range(of: "pendingDownloads.take")!.upperBound
            < fetch.range(of: "FilterListFetchChain.fetch")!.lowerBound,
    "cached payload must be used before FilterListFetchChain.fetch"
)

let refresh = section(updater, "private func refreshFilters(", "struct RefreshFiltersResult")
require(refresh.contains("filtersToRetry"), "failed selected downloads must be retried")
require(
    refresh.contains("runDownloadPass(filters)")
        && refresh.contains("runDownloadPass(filtersToRetry)"),
    "refreshFilters retries only the unsuccessful lists"
)

let selected = section(updates, "func downloadAndApplySelectedUpdates(", "await self.applyChanges")
require(
    selected.contains("updateSelectedFilters")
        && !selected.contains("checkForUpdates"),
    "review apply must download the already-checked selection, not check again"
)

print("PASS: selected update payload reuse")
