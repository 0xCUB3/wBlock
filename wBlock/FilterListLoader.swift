//
//  FilterListLoader.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import Foundation
import wBlockCoreService

class FilterListLoader {
    private let logManager: ConcurrentLogManager
    private let customFilterListsKey = "customFilterLists"
    private let sharedContainerIdentifier = "group.skula.wBlock"

    // Cache the defaults instance
    private let defaults: UserDefaults

    init(logManager: ConcurrentLogManager) {
        self.logManager = logManager
        self.defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
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

        let defaultFilterLists = createDefaultFilterLists()
        
        if let data = defaults.data(forKey: "filterLists"),
           let savedFilterLists = try? JSONDecoder().decode([FilterList].self, from: data) {
            
            // Create a map of default filters by URL for quick lookup
            let defaultFiltersByURL = Dictionary(uniqueKeysWithValues: defaultFilterLists.map { ($0.url, $0) })
            
            // Update saved filters with default properties, preserving user settings
            for savedFilter in savedFilterLists {
                if let defaultFilter = defaultFiltersByURL[savedFilter.url] {
                    // Create updated filter with default properties but preserve user choices
                    let updatedFilter = FilterList(
                        id: savedFilter.id, // Keep the original ID
                        name: defaultFilter.name, // Use default name (may have been updated)
                        url: defaultFilter.url, // Use default URL (may have been updated)
                        category: defaultFilter.category, // Use default category
                        isSelected: savedFilter.isSelected, // Preserve user's selection
                        description: defaultFilter.description, // Use default description (may have been updated)
                        version: savedFilter.version, // Keep version info
                        sourceRuleCount: savedFilter.sourceRuleCount // Keep rule count
                    )
                    filterLists.append(updatedFilter)
                } else {
                    // Keep filters that aren't in defaults (like custom filters)
                    filterLists.append(savedFilter)
                }
            }
            
            // Add any new default filters that weren't in saved data
            let existingURLs = Set(savedFilterLists.map { $0.url })
            for defaultFilter in defaultFilterLists {
                if !existingURLs.contains(defaultFilter.url) {
                    filterLists.append(defaultFilter)
                }
            }
        } else {
            filterLists = defaultFilterLists
        }

        // Handle custom lists separately - these should always be preserved and updated
        let customLists = loadCustomFilterLists()
        
        // Remove any custom filters that are no longer in the custom list
        filterLists.removeAll { filter in 
            filter.category == FilterListCategory.custom && !customLists.contains(where: { $0.url == filter.url })
        }
        
        // Add or update custom filters
        for customFilter in customLists {
            if let existingIndex = filterLists.firstIndex(where: { $0.url == customFilter.url }) {
                // Create updated custom filter with new data but preserve user settings
                let existingFilter = filterLists[existingIndex]
                let updatedCustomFilter = FilterList(
                    id: existingFilter.id, // Keep the original ID
                    name: customFilter.name, // Use custom filter name (may have been updated)
                    url: customFilter.url, // Use custom filter URL
                    category: customFilter.category, // Use custom filter category
                    isSelected: existingFilter.isSelected, // Preserve user's selection
                    description: customFilter.description, // Use custom filter description (may have been updated)
                    version: existingFilter.version, // Keep version info
                    sourceRuleCount: existingFilter.sourceRuleCount // Keep rule count
                )
                filterLists[existingIndex] = updatedCustomFilter
            } else {
                // Add new custom filter
                filterLists.append(customFilter)
            }
        }

        return filterLists
    }

    /// Creates the default set of filter lists
    private func createDefaultFilterLists() -> [FilterList] {
        var filterLists = [
            FilterList(id: UUID(), name: "AdGuard Base Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/2_optimized.txt")!, category: FilterListCategory.ads, isSelected: true,
                       description: "Comprehensive ad-blocking rules by AdGuard."),
            FilterList(id: UUID(), name: "AdGuard Tracking Protection Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/4_optimized.txt")!, category: FilterListCategory.privacy, isSelected: true, description: "Blocks online tracking and web analytics systems."),
            FilterList(id: UUID(), name: "AdGuard Annoyances Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/14_optimized.txt")!, category: FilterListCategory.annoyances, description: "Removes cookie notices, in-page pop-ups, and other annoyances."),
            FilterList(id: UUID(), name: "AdGuard Social Media Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/3_optimized.txt")!, category: FilterListCategory.annoyances, description: "Blocks social media widgets and buttons."),
            FilterList(id: UUID(), name: "Fanboy's Annoyances Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/122_optimized.txt")!, category: FilterListCategory.annoyances, description: "Hides in-page pop-ups, banners, and other unwanted page elements."),
            FilterList(id: UUID(), name: "Fanboy's Social Blocking List", url: URL(string: "https://easylist.to/easylist/fanboy-social.txt")!, category: FilterListCategory.annoyances, description: "Blocks social media content on webpages."),
            FilterList(id: UUID(), name: "Online Malicious URL Blocklist", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/208_optimized.txt")!, category: FilterListCategory.security, isSelected: true, description: "Protects against malicious URLs, phishing sites, and malware."),
            FilterList(id: UUID(), name: "Peter Lowe's Blocklist", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/204_optimized.txt")!, category: FilterListCategory.multipurpose, isSelected: true, description: "Blocks ads and tracking servers to enhance privacy."),
            FilterList(id: UUID(), name: "d3Host List by d3ward", url: URL(string: "https://raw.githubusercontent.com/d3ward/toolz/master/src/d3host.adblock")!, category: FilterListCategory.multipurpose, isSelected: true,
                       description: "Comprehensive block list for ads and trackers."),
            FilterList(id: UUID(), name: "Anti-Adblock List", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/207_optimized.txt")!, category: FilterListCategory.multipurpose, isSelected: true, description: "Bypasses Anti-Adblock scripts used on some websites."),
            FilterList(id: UUID(), name: "Bypass Paywalls Clean Filter", url: URL(string: "https://raw.githubusercontent.com/0xCUB3/Website/refs/heads/main/content/bpc-paywall-filter.txt")!, category: FilterListCategory.multipurpose, description: "Blocks paywall-related elements. Enable the corresponding userscript for best results."),
            FilterList(id: UUID(), name: "AdGuard Experimental Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/5_optimized.txt")!, category: FilterListCategory.experimental, description: "Contains new rules and fixes not yet included in other filters."),

            // Foreign Filter Lists
            FilterList(id: UUID(), name: "AdGuard Spanish & Portuguese Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/9_optimized.txt")!, category: FilterListCategory.foreign),
            FilterList(id: UUID(), name: "Liste FR + AdGuard French Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/16_optimized.txt")!, category: FilterListCategory.foreign),
            FilterList(id: UUID(), name: "EasyList Germany + AdGuard German Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/6_optimized.txt")!, category: FilterListCategory.foreign),
            FilterList(id: UUID(), name: "AdGuard Russian Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/1_optimized.txt")!, category: FilterListCategory.foreign),
            FilterList(id: UUID(), name: "AdGuard Dutch Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/8_optimized.txt")!, category: FilterListCategory.foreign),
            FilterList(id: UUID(), name: "AdGuard Japanese Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/7_optimized.txt")!, category: FilterListCategory.foreign),
            FilterList(id: UUID(), name: "AdGuard Turkish Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/13_optimized.txt")!, category: FilterListCategory.foreign),
            FilterList(id: UUID(), name: "AdGuard Chinese Filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/224_optimized.txt")!, category: FilterListCategory.foreign)
        ]

        #if os(macOS)
        // macOS-only filters too large for iOS
        filterLists.append(contentsOf: [
            FilterList(id: UUID(), name: "EasyPrivacy", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/118_optimized.txt")!, category: FilterListCategory.privacy, isSelected: true, description: "Blocks tracking scripts, web beacons, and other privacy-invasive elements."),
            FilterList(id: UUID(), name: "Hagezi Pro Mini", url: URL(string: "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.mini.txt")!, category: FilterListCategory.multipurpose, isSelected: true, description: "Extensive blocklist targeting ads, trackers, and other unwanted content.")
        ])
        #endif

        // Set default selections for recommended filters
        #if os(macOS)
        let recommendedFilters = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "EasyPrivacy",
            "Online Malicious URL Blocklist",
            "d3Host List by d3ward",
            "AdGuard Annoyances Filter",
            "Anti-Adblock List",
        ]
        #else
        let recommendedFilters = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "Online Malicious URL Blocklist",
            "d3Host List by d3ward",
            "AdGuard Annoyances Filter",
            "Anti-Adblock List"
        ]
        #endif

        for index in filterLists.indices {
            filterLists[index].isSelected = recommendedFilters.contains(filterLists[index].name)
        }

        return filterLists
    }

    /// Saves filter lists to UserDefaults
    func saveFilterLists(_ filterLists: [FilterList]) {
        // Separate default and custom lists before saving
        let defaultLists = filterLists.filter { $0.category != FilterListCategory.custom }
        let customLists = filterLists.filter { $0.category == FilterListCategory.custom }

        if let data = try? JSONEncoder().encode(defaultLists) {
            defaults.set(data, forKey: "filterLists")
        } else {
            Task {
                await ConcurrentLogManager.shared.log("Failed to encode default filterLists for saving.")
            }
        }

        // Save custom lists separately
        saveCustomFilterLists(customLists)

        // Save the selected state
        saveSelectedState(for: filterLists)
    }

    /// Loads selected state for filter lists from UserDefaults
    func loadSelectedState(for filterLists: inout [FilterList]) {
        for index in filterLists.indices {
            let key = "filter_selected_\(filterLists[index].id.uuidString)"
            filterLists[index].isSelected = defaults.object(forKey: key) as? Bool ?? filterLists[index].isSelected
        }
    }

    /// Saves selected state for filter lists to UserDefaults
    func saveSelectedState(for filterLists: [FilterList]) {
        Task.detached(priority: .background) { [defaults] in
            for filter in filterLists {
                let key = "filter_selected_\(filter.id.uuidString)"
                defaults.set(filter.isSelected, forKey: key)
            }
        }
    }

    /// Loads custom filter lists from UserDefaults
    func loadCustomFilterLists() -> [FilterList] {
        if let data = defaults.data(forKey: customFilterListsKey),
           let customLists = try? JSONDecoder().decode([FilterList].self, from: data) {
            return customLists
        }
        return []
    }

    /// Saves custom filter lists to UserDefaults
    func saveCustomFilterLists(_ customFilterLists: [FilterList]) {
        Task.detached(priority: .background) { [defaults, customFilterListsKey] in
            if let data = try? JSONEncoder().encode(customFilterLists) {
                defaults.set(data, forKey: customFilterListsKey)
            } else {
                await ConcurrentLogManager.shared.log("Failed to encode customFilterLists for saving.")
            }
        }
    }

    /// Checks if a filter file exists locally
    func filterFileExists(_ filter: FilterList) -> Bool {
        guard let containerURL = getSharedContainerURL() else { return false }
        return FileManager.default.fileExists(atPath: containerURL.appendingPathComponent("\(filter.name).txt").path)
    }
    
    /// Gets the URL for the shared container
    func getSharedContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier)
    }

    /// Reads the content of a filter list from the local file system
    func readLocalFilterContent(_ filter: FilterList) -> String? {
        guard let containerURL = getSharedContainerURL() else { return nil }
        let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
        
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            Task {
                await ConcurrentLogManager.shared.log("Error reading local filter content for \(filter.name): \(error)")
            }
            return nil
        }
    }
}
