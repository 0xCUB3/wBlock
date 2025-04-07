//
//  FilterListLoader.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//

import Foundation

class FilterListLoader {
    private let logManager: ConcurrentLogManager
    private let customFilterListsKey = "customFilterLists"
    private let sharedContainerIdentifier = "DNP7DGUB7B.wBlock"

    // Cache the defaults instance
    private let defaults = UserDefaults.standard

    init(logManager: ConcurrentLogManager) {
        self.logManager = logManager
    }

    func checkAndCreateGroupFolder() {
        guard let containerURL = getSharedContainerURL() else {
            Task {
                await ConcurrentLogManager.shared.log("Error: Unable to access shared container")
            }
            return
        }

        if !FileManager.default.fileExists(atPath: containerURL.path) {
            do {
                try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true, attributes: nil)
                Task {
                    await ConcurrentLogManager.shared.log("Created shared container directory")
                }
            } catch {
                Task {
                    await ConcurrentLogManager.shared.log("Error creating shared container directory: \(error)")
                }
            }
        }
    }

    /// Loads filter lists from UserDefaults or creates default ones
    func loadFilterLists() -> [FilterList] {
        var filterLists: [FilterList] = []

        if let data = defaults.data(forKey: "filterLists"), // Use cached defaults
           let savedFilterLists = try? JSONDecoder().decode([FilterList].self, from: data) {
            filterLists = savedFilterLists
        } else {
            filterLists = createDefaultFilterLists()
        }

        // Merge with custom lists if they exist
        let customLists = loadCustomFilterLists()
        let customListURLs = Set(customLists.map { $0.url })
        filterLists.removeAll { $0.category == .custom && !customListURLs.contains($0.url) } // Clean up old custom defaults if needed
        filterLists.append(contentsOf: customLists.filter { existingFilter in !filterLists.contains(where: { $0.url == existingFilter.url }) })


        return filterLists
    }

    /// Creates the default set of filter lists
    private func createDefaultFilterLists() -> [FilterList] {
       // --- Keep the existing default lists ---
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
         // Separate default and custom lists before saving
         let defaultLists = filterLists.filter { $0.category != .custom }
         let customLists = filterLists.filter { $0.category == .custom }

         // Save default lists definition (might be redundant if only selection changes)
         // Consider if you *really* need to save the whole default list definition everytime.
         // Maybe only save if the list structure itself changes (new defaults added/removed).
         if let data = try? JSONEncoder().encode(defaultLists) {
             defaults.set(data, forKey: "filterLists")
         } else {
             Task {
                 await ConcurrentLogManager.shared.log("Failed to encode default filterLists for saving.")
             }
         }

         // Save custom lists separately
         saveCustomFilterLists(customLists)

         // Save the selected state (most important part to save frequently)
         saveSelectedState(for: filterLists) // Ensure selection state covers all lists
    }

    /// Loads selected state for filter lists from UserDefaults
    func loadSelectedState(for filterLists: inout [FilterList]) {
        for index in filterLists.indices {
            // Use filter ID for robustness instead of name
            let key = "filter_selected_\(filterLists[index].id.uuidString)"
            // Provide a default value if the key doesn't exist (e.g., use the default selected state)
            filterLists[index].isSelected = defaults.object(forKey: key) as? Bool ?? filterLists[index].isSelected
        }
    }

    /// Saves selected state for filter lists to UserDefaults asynchronously
    func saveSelectedState(for filterLists: [FilterList]) {
        // Perform saving in a background task
        Task.detached(priority: .background) { [defaults] in // Capture defaults
            for filter in filterLists {
                let key = "filter_selected_\(filter.id.uuidString)" // Use ID
                defaults.set(filter.isSelected, forKey: key)
            }
             // synchronize() is generally not needed and can block; avoid it.
             // UserDefaults automatically saves changes periodically.
            // await ConcurrentLogManager.shared.log("Saved selection state.") // Optional logging
        }
    }

    /// Loads custom filter lists from UserDefaults
    func loadCustomFilterLists() -> [FilterList] {
        if let data = defaults.data(forKey: customFilterListsKey), // Use cached defaults
           let customLists = try? JSONDecoder().decode([FilterList].self, from: data) {
            return customLists
        }
        return []
    }

    /// Saves custom filter lists to UserDefaults
    func saveCustomFilterLists(_ customFilterLists: [FilterList]) {
         // Can also run this in background if needed, though likely less frequent than selection changes
        Task.detached(priority: .background) { [defaults, customFilterListsKey] in // Capture necessary vars
            if let data = try? JSONEncoder().encode(customFilterLists) {
                defaults.set(data, forKey: customFilterListsKey)
                // await ConcurrentLogManager.shared.log("Saved custom filter lists.") // Optional
            } else {
                 // Log error if encoding fails
                 await ConcurrentLogManager.shared.log("Failed to encode customFilterLists for saving.")
            }
        }
    }


    /// Checks if a filter file exists locally
    func filterFileExists(_ filter: FilterList) -> Bool {
        guard let containerURL = getSharedContainerURL() else { return false }
        // Check for the JSON rule file, as that's what's actually used
        let fileURL = containerURL.appendingPathComponent("\(filter.name).json")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    func loadFilterRules(for filter: FilterList) -> ([[String: Any]], [[String: Any]]?)? {
        guard let containerURL = getSharedContainerURL() else { return nil }
        let fileURL = containerURL.appendingPathComponent("\(filter.name).json")
        let advancedFileURL = containerURL.appendingPathComponent("\(filter.name)_advanced.json")

        do {
             guard FileManager.default.fileExists(atPath: fileURL.path) else {
                 // If the primary rule file doesn't exist, treat it as empty/error
                 Task { await ConcurrentLogManager.shared.log("Rule file missing for \(filter.name): \(fileURL.path)") }
                 return ([], nil)
             }
            let data = try Data(contentsOf: fileURL)
            let rules = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]

            var advancedRules: [[String: Any]]? = nil
            if FileManager.default.fileExists(atPath: advancedFileURL.path) {
                let advancedData = try Data(contentsOf: advancedFileURL)
                advancedRules = try JSONSerialization.jsonObject(with: advancedData, options: []) as? [[String: Any]]
            }

            return (rules ?? [], advancedRules)
        } catch {
            Task {
                await ConcurrentLogManager.shared.log("Error loading rules for \(filter.name): \(error)")
            }
            return ([], nil)
        }
    }

    func getSharedContainerURL() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier)
    }
}
