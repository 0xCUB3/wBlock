//
//  SharedAutoUpdateManager.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 8/22/25.
//
//  This lightweight manager runs inside extension processes (Safari WebExtension /
//  SFSafariExtensionHandler) to opportunistically check for filter list updates
//  using the shared App Group. When updates are detected it performs a minimal
//  conversion + reload cycle without needing the full UI "applyChanges" flow.
//  It is heavily throttled (default every 6 hours) and designed to minimize
//  data & energy usage:
//    * Conditional requests via If-None-Match / If-Modified-Since when possible
//    * Parallel network checks with TaskGroup
//    * Only performs full conversion if at least one filter actually changed
//
//  NOTE: This intentionally duplicates a subset of logic from AppFilterManager /
//  FilterListUpdater to avoid pulling SwiftUI / app-layer dependencies into
//  extensions. Keep this file pure Foundation + wBlockCoreService.

import Foundation
import os.log
import SafariServices
#if canImport(UIKit)
import UIKit
#endif

/// Actor to ensure we don't run overlapping auto-updates from multiple extension
/// entry points concurrently.
public actor SharedAutoUpdateManager {
    public static let shared = SharedAutoUpdateManager()

    // MARK: Configuration Keys
    private let lastCheckKey = "autoUpdateLastCheck" // Double (timeIntervalSince1970)
    private let nextEligibleKey = "autoUpdateNextEligibleTime" // Double (abs timestamp with jitter)
    private let intervalHoursKey = "autoUpdateIntervalHours" // Double
    private let enabledKey = "autoUpdateEnabled" // Bool
    private let etagStoreKeyPrefix = "filterEtag_" // + filter UUID
    private let lastModifiedStoreKeyPrefix = "filterLastModified_" // + filter UUID
    private let advancedRulesFilenamePrefix = "advanced_" // + bundleIdentifier + .txt
    private let sharedAutoUpdateLogFilename = "auto_update.log"

    // Jitter factors (±10%) to de-synchronize update waves across users
    private let jitterMin: Double = 0.9
    private let jitterMax: Double = 1.1

    // Default interval (6 hours) — conservative to limit energy usage
    private let defaultIntervalHours: Double = 6

    private let log = OSLog(subsystem: "wBlockCoreService", category: "SharedAutoUpdate")

    private init() {}

    // Public entry point invoked by extensions.
    public func maybeRunAutoUpdate(trigger: String) {
        Task { await runIfNeeded(trigger: trigger) }
    }

    /// Returns status about the next eligible auto-update time for UI/logging.
    /// - Returns: (scheduledAt, secondsRemaining, intervalHours). If no schedule yet, scheduledAt is nil.
    public func nextScheduleStatus() async -> (Date?, TimeInterval?, Double) {
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
        let interval = defaults.object(forKey: intervalHoursKey) as? Double ?? defaultIntervalHours
        let now = Date().timeIntervalSince1970
        if let nextEligible = defaults.object(forKey: nextEligibleKey) as? Double {
            let remaining = max(0, nextEligible - now)
            return (Date(timeIntervalSince1970: nextEligible), remaining, interval)
        }
        // Fallback: derive from lastCheck if present, but no jitter window yet
        if let lastCheck = defaults.object(forKey: lastCheckKey) as? Double {
            let theoretical = lastCheck + interval * 3600
            if theoretical <= now { // already due, but no trigger yet
                return (Date(timeIntervalSince1970: now), 0, interval)
            } else {
                return (Date(timeIntervalSince1970: theoretical), theoretical - now, interval)
            }
        }
        // No prior run – return nil schedule
        return (nil, nil, interval)
    }

    // MARK: - Core Logic
    private func runIfNeeded(trigger: String) async {
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
        let now = Date().timeIntervalSince1970

        // Respect enable flag
        if defaults.object(forKey: enabledKey) as? Bool == false {
            os_log("Auto-update disabled (trigger: %{public}@)", log: log, type: .info, trigger)
            return
        }

        let interval = defaults.object(forKey: intervalHoursKey) as? Double ?? defaultIntervalHours

        // New jitter-aware scheduling: prefer nextEligibleTime if present
        if let nextEligible = defaults.object(forKey: nextEligibleKey) as? Double, now < nextEligible {
            appendSharedLog("⏳ Auto-update throttled (trigger: \(trigger)) nextEligible in \(Int(nextEligible - now))s")
            return // Still inside jittered window
        }

        // Backward compatibility: if nextEligible not set, fall back to lastCheck logic once
        if defaults.object(forKey: nextEligibleKey) == nil, let lastCheck = defaults.object(forKey: lastCheckKey) as? Double, now - lastCheck < interval * 3600 {
            return
        }

        // Compute jittered next eligible time and store it up-front to avoid stampede
        let jitterFactor = Double.random(in: jitterMin...jitterMax)
        let nextEligibleTime = now + interval * 3600 * jitterFactor
    defaults.set(nextEligibleTime, forKey: nextEligibleKey)
    defaults.set(now, forKey: lastCheckKey) // Keep legacy key updated too
    appendSharedLog("🔄 Auto-update window reached (trigger: \(trigger)) next window at \(Date(timeIntervalSince1970: nextEligibleTime))")

        do {
            let (allFilters, selectedFilters) = try loadFilterListsFromDefaults(defaults: defaults)
            guard !selectedFilters.isEmpty else {
                appendSharedLog("⚠️ No selected filters; skipping auto-update.")
                return
            }

            let updates = try await checkForUpdates(filters: selectedFilters, defaults: defaults)
            guard !updates.isEmpty else {
                appendSharedLog("✅ No filter updates found (trigger: \(trigger))")
                return
            }

            os_log("Found %d filter updates (trigger: %{public}@) — applying", log: log, type: .info, updates.count, trigger)
            appendSharedLog("📥 Updates detected: \(updates.map { $0.name }.joined(separator: ", "))")

            // Fetch & store updated content
            let updatedFilterSet = try await fetchAndStoreFilters(updates, defaults: defaults)
            appendSharedLog("📦 Downloaded & stored \(updatedFilterSet.count) updated filter(s)")

            // Merge updated filters back into full list model
            var merged = allFilters
            for updated in updatedFilterSet {
                if let idx = merged.firstIndex(where: { $0.id == updated.id }) {
                    merged[idx] = updated
                }
            }

            // Persist metadata (versions, counts)
            saveFilterListsToDefaults(merged, defaults: defaults)

            // Determine impacted categories for partial target reconversion
            let updatedCategorySet = Set(updatedFilterSet.map { $0.category })

            // Re-convert & reload only impacted targets; rebuild engine from per-target stored advanced rules
            try await rebuildAndReload(selectedFilters: merged.filter { $0.isSelected }, updatedCategories: updatedCategorySet)
            appendSharedLog("✅ Auto-update cycle complete (updated categories: \(updatedCategorySet.map{ $0.rawValue }.joined(separator: ", "))) ")
        } catch {
            os_log("Auto-update failed: %{public}@", log: log, type: .error, String(describing: error))
            appendSharedLog("❌ Auto-update failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Loading / Saving
    private func loadFilterListsFromDefaults(defaults: UserDefaults) throws -> ([FilterList], [FilterList]) {
        var lists: [FilterList] = []
        if let data = defaults.data(forKey: "filterLists"), let decoded = try? JSONDecoder().decode([FilterList].self, from: data) { lists.append(contentsOf: decoded) }
        if let customData = defaults.data(forKey: "customFilterLists"), let decodedCustom = try? JSONDecoder().decode([FilterList].self, from: customData) { lists.append(contentsOf: decodedCustom) }
        // Restore selection state
        for idx in lists.indices {
            let key = "filter_selected_\(lists[idx].id.uuidString)"
            if let sel = defaults.object(forKey: key) as? Bool { lists[idx].isSelected = sel }
        }
        let selected = lists.filter { $0.isSelected }
        return (lists, selected)
    }

    private func saveFilterListsToDefaults(_ lists: [FilterList], defaults: UserDefaults) {
        let defaultLists = lists.filter { $0.category != .custom }
        let customLists = lists.filter { $0.category == .custom }
        if let data = try? JSONEncoder().encode(defaultLists) { defaults.set(data, forKey: "filterLists") }
        if let cdata = try? JSONEncoder().encode(customLists) { defaults.set(cdata, forKey: "customFilterLists") }
        for fl in lists { defaults.set(fl.isSelected, forKey: "filter_selected_\(fl.id.uuidString)") }
    }

    // MARK: - Update Detection
    private func checkForUpdates(filters: [FilterList], defaults: UserDefaults) async throws -> [FilterList] {
        var result: [FilterList] = []
        await withTaskGroup(of: (FilterList, Bool).self) { group in
            for f in filters { group.addTask { (f, await self.hasUpdate(for: f, defaults: defaults)) } }
            for await (f, needs) in group where needs { result.append(f) }
        }
        return result
    }

    private func hasUpdate(for filter: FilterList, defaults: UserDefaults) async -> Bool {
        // Compare remote signature (ETag/Last-Modified) – fall back to full body diff
        var request = URLRequest(url: filter.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)

        let etagKey = etagStoreKeyPrefix + filter.id.uuidString
        let lmKey = lastModifiedStoreKeyPrefix + filter.id.uuidString

        if let etag = defaults.string(forKey: etagKey) { request.addValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lm = defaults.string(forKey: lmKey) { request.addValue(lm, forHTTPHeaderField: "If-Modified-Since") }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            if http.statusCode == 304 { return false } // Not modified via conditional request

            // Update stored validators for later
            if let newEtag = http.value(forHTTPHeaderField: "ETag") { defaults.set(newEtag, forKey: etagKey) }
            if let newLM = http.value(forHTTPHeaderField: "Last-Modified") { defaults.set(newLM, forKey: lmKey) }

            // Compare body with local file if exists
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) {
                let localURL = containerURL.appendingPathComponent("\(filter.name).txt")
                if FileManager.default.fileExists(atPath: localURL.path),
                   let localData = try? Data(contentsOf: localURL),
                   localData == data { return false }
            }
            // Content differs or no local file — treat as update
            return true
        } catch {
            os_log("Update check error for %{public}@ – %{public}@", log: log, type: .error, filter.name, error.localizedDescription)
            return false
        }
    }

    // MARK: - Fetch & Store
    private func fetchAndStoreFilters(_ filters: [FilterList], defaults: UserDefaults) async throws -> [FilterList] {
        var updated: [FilterList] = []
        await withTaskGroup(of: FilterList?.self) { group in
            for filter in filters {
                group.addTask { await self.fetchOne(filter) }
            }
            for await maybe in group { if let f = maybe { updated.append(f) } }
        }
        return updated
    }

    private func fetchOne(_ filter: FilterList) async -> FilterList? {
        do {
            let (data, response) = try await URLSession.shared.data(from: filter.url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let content = String(data: data, encoding: .utf8) else { return nil }
            let meta = parseMetadata(from: content)
            let ruleCount = countRulesInContent(content: content)
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) {
                try? content.write(to: containerURL.appendingPathComponent("\(filter.name).txt"), atomically: true, encoding: .utf8)
            }
            var updated = filter
            if let version = meta.version, !version.isEmpty { updated.version = version }
            if let desc = meta.description, !desc.isEmpty { updated.description = desc }
            updated.sourceRuleCount = ruleCount
            appendSharedLog("↻ Updated filter: \(filter.name) (version: \(updated.version), rules: \(ruleCount))")
            return updated
        } catch {
            os_log("Fetch error for %{public}@ – %{public}@", log: log, type: .error, filter.name, error.localizedDescription)
            appendSharedLog("⚠️ Failed updating filter: \(filter.name) – \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Conversion & Reload
    private func rebuildAndReload(selectedFilters: [FilterList], updatedCategories: Set<FilterListCategory>) async throws {
        // Build rules per target using same mapping logic as main app
        #if os(iOS)
        let detectedPlatform: Platform = .iOS
        #else
        let detectedPlatform: Platform = .macOS
        #endif
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: detectedPlatform)
        var advancedRulesSnippets: [String] = []

        for target in targets {
            let targetCategories: [FilterListCategory] = {
                if let secondary = target.secondaryCategory { return [target.primaryCategory, secondary] }
                return [target.primaryCategory]
            }()

            let intersects = !updatedCategories.isDisjoint(with: targetCategories)
            let existingAdvanced = loadStoredAdvancedRules(for: target)

            // Decide if we must reconvert this target
            let mustReconvert: Bool = intersects || existingAdvanced == nil
            if mustReconvert {
                // Rebuild combined raw rules for this target from selected filters
                let filtersForTarget = selectedFilters.filter { targetCategories.contains($0.category) }
                var combined = ""
                if !filtersForTarget.isEmpty, let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) {
                    for f in filtersForTarget {
                        let fileURL = containerURL.appendingPathComponent("\(f.name).txt")
                        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                            combined += content + "\n"
                        }
                    }
                }
                appendSharedLog("🛠 Reconverting target: \(target.bundleIdentifier) categories: \(targetCategories.map{ $0.rawValue }.joined(separator: ", ")) filters: \(filtersForTarget.map{ $0.name }.joined(separator: ", "))")
                let conversion = ContentBlockerService.convertFilter(rules: combined.isEmpty ? "" : combined, groupIdentifier: GroupIdentifier.shared.value, targetRulesFilename: target.rulesFilename)
                if let adv = conversion.advancedRulesText, !adv.isEmpty {
                    storeAdvancedRules(adv, for: target)
                    advancedRulesSnippets.append(adv)
                } else {
                    // Clear stored file if previously had advanced rules
                    removeStoredAdvancedRules(for: target)
                }
                _ = ContentBlockerService.reloadContentBlocker(withIdentifier: target.bundleIdentifier)
                appendSharedLog("🔁 Reloaded target extension: \(target.bundleIdentifier)")
            } else if let existingAdvanced = existingAdvanced, !existingAdvanced.isEmpty {
                // Reuse stored advanced rules without reconversion
                advancedRulesSnippets.append(existingAdvanced)
                appendSharedLog("♻️ Reused cached advanced rules for target: \(target.bundleIdentifier)")
            }
        }

        if !advancedRulesSnippets.isEmpty {
            ContentBlockerService.buildCombinedFilterEngine(combinedAdvancedRules: advancedRulesSnippets.joined(separator: "\n"), groupIdentifier: GroupIdentifier.shared.value)
            appendSharedLog("🧠 Rebuilt advanced engine with \(advancedRulesSnippets.count) snippet(s)")
        } else {
            ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)
            appendSharedLog("🧹 Cleared advanced engine (no advanced rules)")
        }
    }

    // MARK: - Helpers
    private func countRulesInContent(content: String) -> Int {
        content.split(separator: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && !trimmed.hasPrefix("!") && !trimmed.hasPrefix("[") && !trimmed.hasPrefix("#")
        }.count
    }

    private func parseMetadata(from content: String) -> (title: String?, description: String?, version: String?) {
        var title: String?; var description: String?; var version: String?
        let patterns: [String: String] = [
            "Title": "^!\\s*Title\\s*:?\\s*(.*)$",
            "Description": "^!\\s*Description\\s*:?\\s*(.*)$",
            "Version": "^!\\s*(?:version|last modified|updated)\\s*:?\\s*(.*)$"
        ]
        for line in content.split(separator: "\n").prefix(80) { // Scan only first 80 lines
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for (key, pattern) in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
                   match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: trimmed) {
                    let raw = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
                    let clean = raw.replacingOccurrences(of: "/", with: " & ")
                    switch key {
                    case "Title": title = clean
                    case "Description": description = clean
                    case "Version": version = clean
                    default: break
                    }
                }
            }
            if title != nil, description != nil, version != nil { break }
        }
        return (title, description, version)
    }

    // MARK: - Advanced Rules Persistence
    private func advancedRulesURL(for target: ContentBlockerTargetInfo) -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else { return nil }
        return containerURL.appendingPathComponent("\(advancedRulesFilenamePrefix)\(target.bundleIdentifier).txt")
    }

    private func storeAdvancedRules(_ text: String, for target: ContentBlockerTargetInfo) {
        guard let url = advancedRulesURL(for: target) else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadStoredAdvancedRules(for target: ContentBlockerTargetInfo) -> String? {
        guard let url = advancedRulesURL(for: target), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func removeStoredAdvancedRules(for target: ContentBlockerTargetInfo) {
        guard let url = advancedRulesURL(for: target), FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Shared Log (File-Based for Extensions)
    private func appendSharedLog(_ line: String) {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else { return }
        let logURL = base.appendingPathComponent(sharedAutoUpdateLogFilename)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let full = "[\(timestamp)] \(line)\n"
        if let data = full.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    // Removed runtime heuristic; compile-time selection is sufficient.
}
