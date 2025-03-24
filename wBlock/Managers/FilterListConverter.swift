//
//  FilterListConverter.swift
//  wBlock
//
//  Created by Alexander Skula on 7/17/24.
//

import Foundation
import ContentBlockerConverter

class FilterListConverter {
    private let logManager: ConcurrentLogManager

    init(logManager: ConcurrentLogManager) {
        self.logManager = logManager
    }

    /// Converts Adblock rules to Safari-compatible JSON and saves them
    func convertAndSaveRules(_ rules: [String], for filter: FilterList) async {
        do {
            let converter = ContentBlockerConverter()
            let result = converter.convertArray(rules: rules, safariVersion: .safari16_4, optimize: true, advancedBlocking: true)

            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "DNP7DGUB7B.wBlock") else {
                await ConcurrentLogManager.shared.log("Error: Unable to access shared container")
                return
            }

            func saveJson(data: String?, filename: String) {
                guard let jsonData = data?.data(using: .utf8),
                    let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]],
                    let limitedJsonData = try? JSONSerialization.data(withJSONObject: Array(jsonArray.prefix(result.convertedCount)), options: .prettyPrinted)
                    else {
                        Task {
                            await ConcurrentLogManager.shared.log("Error: Failed to process JSON data for \(filename)")
                        }
                    return
                    }

                do {
                    try limitedJsonData.write(to: containerURL.appendingPathComponent(filename))
                    Task {
                        await ConcurrentLogManager.shared.log("Wrote \(filename)")
                    }
                } catch {
                    Task {
                        await ConcurrentLogManager.shared.log("Error writing \(filename): \(error.localizedDescription)")
                    }
                }
            }

            saveJson(data: result.converted, filename: "\(filter.name).json")
            saveJson(data: result.advancedBlocking, filename: "\(filter.name)_advanced.json")

            // Log conversion statistics
            let standardRulesCount = result.convertedCount

            // Get advanced rules count by parsing the JSON if available
            var advancedRulesCount = 0
            if let advancedData = result.advancedBlocking?.data(using: .utf8),
               let advancedArray = try? JSONSerialization.jsonObject(with: advancedData) as? [[String: Any]] {
                advancedRulesCount = advancedArray.count
            }

            await ConcurrentLogManager.shared.log("Converted \(filter.name): \(standardRulesCount) standard rules, \(advancedRulesCount) advanced rules")

        } catch {
            await ConcurrentLogManager.shared.log("Error converting \(filter.name): \(error)")
        }
    }

    /// Merges multiple filter rule sets into a single set
    func mergeFilterRules(from filterLists: [FilterList]) async -> ([[String: Any]], [[String: Any]]) {
        var allRules: [[String: Any]] = []
        var advancedRules: [[String: Any]] = []

        for filter in filterLists {
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "DNP7DGUB7B.wBlock") {
                let fileURL = containerURL.appendingPathComponent("\(filter.name).json")
                let advancedFileURL = containerURL.appendingPathComponent("\(filter.name)_advanced.json")

                do {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        let data = try Data(contentsOf: fileURL)
                        if let rules = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                            allRules.append(contentsOf: rules)
                        }
                    }

                    if FileManager.default.fileExists(atPath: advancedFileURL.path) {
                        let advancedData = try Data(contentsOf: advancedFileURL)
                        if let rules = try JSONSerialization.jsonObject(with: advancedData, options: []) as? [[String: Any]] {
                            advancedRules.append(contentsOf: rules)
                        }
                    }
                } catch {
                    await ConcurrentLogManager.shared.log("Error loading rules for \(filter.name): \(error)")
                }
            }
        }

        return (allRules, advancedRules)
    }

    /// Optimizes a set of rules by removing duplicates
    func optimizeRules(_ rules: [[String: Any]]) -> [[String: Any]] {
        // This is a simple implementation that could be expanded with more sophisticated optimization
        var uniqueRules: [[String: Any]] = []
        var seenRules = Set<String>()

        for rule in rules {
            if let ruleData = try? JSONSerialization.data(withJSONObject: rule),
               let ruleString = String(data: ruleData, encoding: .utf8) {
                if !seenRules.contains(ruleString) {
                    seenRules.insert(ruleString)
                    uniqueRules.append(rule)
                }
            } else {
                // If we can't serialize the rule, include it anyway
                uniqueRules.append(rule)
            }
        }

        return uniqueRules
    }
}
