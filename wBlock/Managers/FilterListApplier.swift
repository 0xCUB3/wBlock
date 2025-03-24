//
//  FilterListApplier.swift
//  wBlock
//
//  Created by Alexander Skula on 7/17/24.
//

import Foundation
import SafariServices

class FilterListApplier {
    private let contentBlockerIdentifier = "com.0xcube.wBlock.wBlockFilters"
    private let sharedContainerIdentifier = "DNP7DGUB7B.wBlock"
    private let logManager: ConcurrentLogManager
    private let converter: FilterListConverter?

    init(logManager: ConcurrentLogManager, converter: FilterListConverter? = nil) {
        self.logManager = logManager
        self.converter = converter
    }

    /// Checks if the blocker list exists and creates it if needed
    func checkAndCreateBlockerList(filterLists: [FilterList]) async {
        guard let containerURL = getSharedContainerURL() else {
            await ConcurrentLogManager.shared.log("Error: Unable to access shared container")
            return
        }

        let blockerListURL = containerURL.appendingPathComponent("blockerList.json")
        let advancedBlockingURL = containerURL.appendingPathComponent("advancedBlocking.json")

        if !FileManager.default.fileExists(atPath: blockerListURL.path) {
            await ConcurrentLogManager.shared.log("blockerList.json not found. Creating it...")
            let selectedFilters = filterLists.filter { $0.isSelected }
            var allRules: [[String: Any]] = []
            var advancedRules: [[String: Any]] = []

            for filter in selectedFilters {
                if let (rules, advanced) = await loadFilterRules(for: filter) {
                    allRules.append(contentsOf: rules)
                    if let advanced = advanced {
                        advancedRules.append(contentsOf: advanced)
                    }
                }
            }

            saveBlockerList(allRules)
            saveAdvancedBlockerList(advancedRules)
        } else {
            await ConcurrentLogManager.shared.log("blockerList.json found.")
        }
    }

    /// Applies changes to the content blocker
    func applyChanges(filterLists: [FilterList], progressCallback: @escaping (Float) -> Void) async {
        let selectedFilters = filterLists.filter { $0.isSelected }
        let totalSteps = Float(selectedFilters.count)
        var completedSteps: Float = 0

        var allRules: [[String: Any]] = []
        var advancedRules: [[String: Any]] = []

        // Collect all rules first
        await withTaskGroup(of: (FilterList, [[String: Any]], [[String: Any]]?).self) { group in
            for filter in selectedFilters {
                group.addTask {
                    if let (rules, advanced) = await self.loadFilterRules(for: filter) {
                        return (filter, rules, advanced)
                    }
                    return (filter, [], nil)
                }
            }

            for await (_, rules, advanced) in group {
                allRules.append(contentsOf: rules)
                if let advanced = advanced {
                    advancedRules.append(contentsOf: advanced)
                }
                completedSteps += 1
                progressCallback(completedSteps / totalSteps)
            }
        }

        // Check rule count
        let totalRuleCount = allRules.count + advancedRules.count
        if totalRuleCount > 150000 {
            // Show alert and abort
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Too Many Rules"
                alert.informativeText = "The selected filters would create \(totalRuleCount) rules, which exceeds the maximum limit of 150,000. Please disable some filters and try again."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }

        // Optimize rules if converter is available
        if let converter = converter {
            allRules = converter.optimizeRules(allRules)
            advancedRules = converter.optimizeRules(advancedRules)
        }

        saveBlockerList(allRules)
        saveAdvancedBlockerList(advancedRules)
        await reloadContentBlocker()
    }

    /// Saves the blocker list to file storage
    func saveBlockerList(_ rules: [[String: Any]]) {
        do {
            if let jsonData = try? JSONSerialization.data(withJSONObject: rules, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                try FileStorage.shared.saveJSON(jsonString, filename: "blockerList.json")

                // Only store the state in UserDefaults
                if let containerDefaults = UserDefaults(suiteName: sharedContainerIdentifier) {
                    containerDefaults.set(true, forKey: "blockerList")
                    containerDefaults.synchronize()
                }
                Task {
                    await ConcurrentLogManager.shared.log("Successfully saved blockerList to file storage (\(rules.count) rules)")
                }
            } else {
                Task {
                    await ConcurrentLogManager.shared.log("Error: Unable to serialize blockerList JSON data")
                }
            }
        } catch {
            Task {
                await ConcurrentLogManager.shared.log("Error saving blockerList: \(error)")
            }
        }
    }

    /// Saves the advanced blocker list to file storage
    func saveAdvancedBlockerList(_ rules: [[String: Any]]) {
        do {
            if let jsonData = try? JSONSerialization.data(withJSONObject: rules, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                try FileStorage.shared.saveJSON(jsonString, filename: "advancedBlocking.json")

                // Only store the state in UserDefaults
                if let containerDefaults = UserDefaults(suiteName: sharedContainerIdentifier) {
                    containerDefaults.set(true, forKey: "advancedBlocking")
                    containerDefaults.synchronize()
                }
                Task {
                    await ConcurrentLogManager.shared.log("Successfully saved advancedBlocking to file storage (\(rules.count) rules)")
                }
            } else {
                Task {
                    await ConcurrentLogManager.shared.log("Error: Unable to serialize advancedBlocking JSON data")
                }
            }
        } catch {
            Task {
                await ConcurrentLogManager.shared.log("Error saving advancedBlocking: \(error)")
            }
        }
    }

    /// Reloads the content blocker in Safari
    func reloadContentBlocker() async {
        do {
            let ruleCount = try (JSONSerialization.jsonObject(with: FileStorage.shared.loadJSON(filename: "blockerList.json").data(using: .utf8)!) as? [[String: Any]])?.count ?? 0
            await ConcurrentLogManager.shared.log("Reloading content blocker (\(ruleCount) rules)")

            try await SFContentBlockerManager.reloadContentBlocker(withIdentifier: contentBlockerIdentifier)
            await ConcurrentLogManager.shared.log("Content blocker reloaded successfully")
        } catch {
            await ConcurrentLogManager.shared.log("Error reloading content blocker: \(error)")
        }
    }

    /// Loads filter rules from a JSON file
    private func loadFilterRules(for filter: FilterList) async -> ([[String: Any]], [[String: Any]]?)? {
        guard let containerURL = getSharedContainerURL() else { return nil }
        let fileURL = containerURL.appendingPathComponent("\(filter.name).json")
        let advancedFileURL = containerURL.appendingPathComponent("\(filter.name)_advanced.json")

        do {
            let data = try Data(contentsOf: fileURL)
            let rules = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]

            var advancedRules: [[String: Any]]? = nil
            if FileManager.default.fileExists(atPath: advancedFileURL.path) {
                let advancedData = try Data(contentsOf: advancedFileURL)
                advancedRules = try JSONSerialization.jsonObject(with: advancedData, options: []) as? [[String: Any]]
            }

            return (rules ?? [], advancedRules)
        } catch {
            await ConcurrentLogManager.shared.log("Error loading rules for \(filter.name): \(error)")
            return nil
        }
    }

    /// Retrieves the shared container URL
    private func getSharedContainerURL() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier)
    }
}
