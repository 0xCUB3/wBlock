//
//  FilterListLoader.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//

import Foundation

class FilterListLoader {
    private let logManager: LogManager
    private let customFilterListsKey = "customFilterLists"
    private let sharedContainerIdentifier = "group.com.0xcube.wBlock"

    init(logManager: LogManager) {
        self.logManager = logManager
    }

    /// Checks and creates the group folder if it doesn't exist
    func checkAndCreateGroupFolder() {
        guard let containerURL = getSharedContainerURL() else {
            logManager.appendLog("Error: Unable to access shared container")
            return
        }

        if !FileManager.default.fileExists(atPath: containerURL.path) {
            do {
                try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true, attributes: nil)
                logManager.appendLog("Created shared container directory")
            } catch {
                logManager.appendLog("Error creating shared container directory: \(error)")
            }
        }
    }

    /// Loads filter lists from UserDefaults or creates default ones
    func loadFilterLists() -> [FilterList] {
        var filterLists: [FilterList] = []

        if let data = UserDefaults.standard.data(forKey: "filterLists"),
           let savedFilterLists = try? JSONDecoder().decode([FilterList].self, from: data) {
            filterLists = savedFilterLists
        } else {
            filterLists = createDefaultFilterLists()
        }

        return filterLists
    }

    /// Creates the default set of filter lists
    private func createDefaultFilterLists() -> [FilterList] {
        var filterLists = [
            FilterList(id: UUID(), name: "AdGuard Base Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/2_optimized.txt")!, category: .ads, isSelected: true,
                       description: "Comprehensive ad-blocking rules by AdGuard."),
            FilterList(id: UUID(), name: "AdGuard Tracking Protection Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/4_optimized.txt")!, category: .privacy, isSelected: true, description: "Blocks online tracking and web analytics systems."),
            FilterList(id: UUID(), name: "AdGuard Annoyances Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/14_optimized.txt")!, category: .annoyances, description: "Removes cookie notices, in-page pop-ups, and other annoyances."),
            FilterList(id: UUID(), name: "AdGuard Social Media Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/3_optimized.txt")!, category: .annoyances, description: "Blocks social media widgets and buttons."),
            FilterList(id: UUID(), name: "Fanboy's Annoyances Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/122_optimized.txt")!, category: .annoyances, description: "Hides in-page pop-ups, banners, and other unwanted page elements."),
            FilterList(id: UUID(), name: "Fanboy's Social Blocking List", url: URL(string: "https://easylist.to/easylist/fanboy-social.txt")!, category: .annoyances, description: "Blocks social media content on webpages."),
            FilterList(id: UUID(), name: "EasyPrivacy", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/118_optimized.txt")!, category: .privacy, isSelected: true, description: "Blocks tracking scripts, web beacons, and other privacy-invasive elements."),
            FilterList(id: UUID(), name: "Online Malicious URL Blocklist", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/208_optimized.txt")!, category: .security, isSelected: true, description: "Protects against malicious URLs, phishing sites, and malware."),
            FilterList(id: UUID(), name: "Peter Lowe's Blocklist", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/204_optimized.txt")!, category: .multipurpose, isSelected: true, description: "Blocks ads and tracking servers to enhance privacy."),
            FilterList(id: UUID(), name: "Hagezi Pro Mini", url: URL(string: "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.mini.txt")!, category: .multipurpose, isSelected: true, description: "Extensive blocklist targeting ads, trackers, and other unwanted content."),
            FilterList(id: UUID(), name: "d3Host List by d3ward", url: URL(string: "https://raw.githubusercontent.com/d3ward/toolz/master/src/d3host.adblock")!, category: .multipurpose, isSelected: true,
                       description: "Comprehensive block list for ads and trackers."),
            FilterList(id: UUID(), name: "Anti-Adblock List", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/207_optimized.txt")!, category: .multipurpose, isSelected: true, description: "Bypasses Anti-Adblock scripts used on some websites."),
            FilterList(id: UUID(), name: "AdGuard Experimental Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/5_optimized.txt")!, category: .experimental, description: "Contains new rules and fixes not yet included in other filters."),

            // --- Foreign Filter Lists ---

            // Spanish & Portuguese
            FilterList(id: UUID(), name: "AdGuard Spanish & Portuguese Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/9_optimized.txt")!, category: .foreign),
            
            // French
            FilterList(id: UUID(), name: "Liste FR + AdGuard French Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/16_optimized.txt")!, category: .foreign),

            // German
            FilterList(id: UUID(), name: "EasyList Germany + AdGuard German Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/6_optimized.txt")!, category: .foreign),

            // Russian
            FilterList(id: UUID(), name: "AdGuard Russian Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/1_optimized.txt")!, category: .foreign),

            // Dutch
            FilterList(id: UUID(), name: "AdGuard Dutch Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/8_optimized.txt")!, category: .foreign),

            // Japanese
            FilterList(id: UUID(), name: "AdGuard Japanese Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/7_optimized.txt")!, category: .foreign),

            // Turkish
            FilterList(id: UUID(), name: "AdGuard Turkish Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/13_optimized.txt")!, category: .foreign),

            // Chinese
            FilterList(id: UUID(), name: "AdGuard Chinese Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/224_optimized.txt")!, category: .foreign)
        ]

        // Set default selections for recommended filters
        let recommendedFilters = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "AdGuard Annoyances Filter",
            "EasyPrivacy",
            "Online Malicious URL Blocklist",
            "d3Host List by d3ward",
            "Anti-Adblock List"
        ]

        for index in filterLists.indices {
            filterLists[index].isSelected = recommendedFilters.contains(filterLists[index].name)
        }

        return filterLists
    }

    /// Saves filter lists to UserDefaults
    func saveFilterLists(_ filterLists: [FilterList]) {
        if let data = try? JSONEncoder().encode(filterLists) {
            UserDefaults.standard.set(data, forKey: "filterLists")
        } else {
            logManager.appendLog("Failed to encode filterLists for saving.")
        }
    }

    /// Loads selected state for filter lists from UserDefaults
    func loadSelectedState(for filterLists: inout [FilterList]) {
        let defaults = UserDefaults.standard
        for (index, filter) in filterLists.enumerated() {
            filterLists[index].isSelected = defaults.bool(forKey: "filter_\(filter.name)")
        }
    }

    /// Saves selected state for filter lists to UserDefaults
    func saveSelectedState(for filterLists: [FilterList]) {
        let defaults = UserDefaults.standard
        for filter in filterLists {
            defaults.set(filter.isSelected, forKey: "filter_\(filter.name)")
        }
    }

    /// Loads custom filter lists from UserDefaults
    func loadCustomFilterLists() -> [FilterList] {
        if let data = UserDefaults.standard.data(forKey: customFilterListsKey),
           let customLists = try? JSONDecoder().decode([FilterList].self, from: data) {
            return customLists
        }
        return []
    }

    /// Saves custom filter lists to UserDefaults
    func saveCustomFilterLists(_ customFilterLists: [FilterList]) {
        if let data = try? JSONEncoder().encode(customFilterLists) {
            UserDefaults.standard.set(data, forKey: customFilterListsKey)
        }
    }

    /// Checks if a filter file exists locally
    func filterFileExists(_ filter: FilterList) -> Bool {
        guard let containerURL = getSharedContainerURL() else { return false }
        let fileURL = containerURL.appendingPathComponent("\(filter.name).json")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Loads filter rules from a JSON file
    func loadFilterRules(for filter: FilterList) -> ([[String: Any]], [[String: Any]]?)? {
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
            logManager.appendLog("Error loading rules for \(filter.name): \(error)")
            return nil
        }
    }

    /// Retrieves the shared container URL
    func getSharedContainerURL() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier)
    }
}
