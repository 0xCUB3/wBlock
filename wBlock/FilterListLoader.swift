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

        if let data = defaults.data(forKey: "filterLists"),
           let savedFilterLists = try? JSONDecoder().decode([FilterList].self, from: data) {
            filterLists = savedFilterLists
        } else {
            filterLists = createDefaultFilterLists()
        }

        // Merge with custom lists if they exist
        let customLists = loadCustomFilterLists()
        let customListURLs = Set(customLists.map { $0.url })
        filterLists.removeAll { $0.category == FilterListCategory.custom && !customListURLs.contains($0.url) }
        filterLists.append(contentsOf: customLists.filter { existingFilter in !filterLists.contains(where: { $0.url == existingFilter.url }) })

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
        // Add macOS-only filters
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
            "Anti-Adblock List",
            "Hagezi Pro Mini"
        ]
        #else
        let recommendedFilters = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "Online Malicious URL Blocklist",
            "d3Host List by d3ward",
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
}
