//
//  BlocklistManager.swift
//  wBlock Origin
//
//  Created by Alexander Skula on 7/17/24.
//

import Foundation
import Combine
import SafariServices
import ContentBlockerConverter
import UserNotifications

enum FilterListCategory: String, CaseIterable, Identifiable {
    case all = "All", ads = "Ads", privacy = "Privacy", security = "Security", multipurpose = "Multipurpose", annoyances = "Annoyances", experimental = "Experimental", foreign = "Foreign"
    var id: String { self.rawValue }
}

struct FilterList: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let category: FilterListCategory
    var isSelected: Bool = false
}

enum LogLevel: String {
    case info = "INFO"
    case debug = "DEBUG"
    case warning = "WARNING"
    case error = "ERROR"
}

@MainActor
class FilterListManager: ObservableObject {
    @Published var filterLists: [FilterList] = []
    @Published var isUpdating = false
    @Published var progress: Float = 0
    @Published var missingFilters: [FilterList] = []
    @Published var logs: String = ""
    @Published var showProgressView = false
    @Published var availableUpdates: [FilterList] = []
    @Published var showingUpdatePopup = false
    @Published var hasUnappliedChanges = false
    @Published var showMissingFiltersSheet = false
    @Published var showRecommendedFiltersAlert = false
    @Published var showResetToDefaultAlert = false
    @Published var showingNoUpdatesAlert = false
    
    private let contentBlockerIdentifier = "app.0xcube.wBlock.wBlockFilters"
    private let sharedContainerIdentifier = "group.app.0xcube.wBlock"
    
    init() {
        checkAndCreateGroupFolder()
        loadFilterLists()
        loadSelectedState()
        checkAndCreateBlockerList()
        checkAndEnableFilters()
        clearLogs()
    }
    
    func loadFilterLists() {
        filterLists = [
            FilterList(name: "AdGuard Base filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/2_optimized.txt")!, category: .ads, isSelected: true),
            FilterList(name: "AdGuard Tracking Protection filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/4_optimized.txt")!, category: .privacy, isSelected: true),
            FilterList(name: "AdGuard Annoyances filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/14_optimized.txt")!, category: .annoyances),
            FilterList(name: "AdGuard Social Media filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/3_optimized.txt")!, category: .annoyances),
            FilterList(name: "Fanboy's Annoyances filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/122_optimized.txt")!, category: .annoyances),
            FilterList(name: "EasyPrivacy", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/118_optimized.txt")!, category: .privacy, isSelected: true),
            FilterList(name: "Online Malicious URL Blocklist", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/208_optimized.txt")!, category: .security, isSelected: true),
            FilterList(name: "Peter Lowe's Blocklist", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/204_optimized.txt")!, category: .multipurpose, isSelected: true),
            FilterList(name: "Hagezi Pro mini", url: URL(string: "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.mini.txt")!, category: .multipurpose, isSelected: true),
            FilterList(name: "d3Host List by d3ward", url: URL(string: "https://raw.githubusercontent.com/d3ward/toolz/master/src/d3host.adblock")!, category: .multipurpose, isSelected: true),
            FilterList(name: "Anti-Adblock List", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/207_optimized.txt")!, category: .multipurpose, isSelected: true),
            FilterList(name: "AdGuard Experimental filter", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/5_optimized.txt")!, category: .experimental),
            
            // --- Foreign Filter Lists ---
            // Spanish
            FilterList(name: "Lista de bloqueo de dominios españoles", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/126_optimized.txt")!, category: .foreign),

            // French
            FilterList(name: "Liste française de blocage des publicités", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/120_optimized.txt")!, category: .foreign),

            // German
            FilterList(name: "Deutsche Werbeblocker-Liste", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/119_optimized.txt")!, category: .foreign),

            // Russian
            FilterList(name: "Русский фильтр AdGuard", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/121_optimized.txt")!, category: .foreign),

            // Dutch
            FilterList(name: "Nederlandse advertentieblokkeringlijst", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/124_optimized.txt")!, category: .foreign),

            // Japanese
            FilterList(name: "日本語の広告ブロックリスト", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/123_optimized.txt")!, category: .foreign),

            // Portuguese (Brazil)
            FilterList(name: "Lista brasileira de bloqueio de anúncios", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/127_optimized.txt")!, category: .foreign),

            // Korean
            FilterList(name: "한국어 광고 차단 목록", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/125_optimized.txt")!, category: .foreign),

            // Turkish
            FilterList(name: "Türkçe reklam engelleme listesi", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/128_optimized.txt")!, category: .foreign),
            
            // Chinese Simplified
            FilterList(name: "中文简体广告过滤列表", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/129_optimized.txt")!, category: .foreign),
            
            // Chinese Traditional
            FilterList(name: "中文繁體廣告過濾清單", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/130_optimized.txt")!, category: .foreign)
        ]
    }
    
    private func loadSelectedState() {
        let defaults = UserDefaults.standard
        for (index, filter) in filterLists.enumerated() {
            filterLists[index].isSelected = defaults.bool(forKey: "filter_\(filter.name)")
        }
    }
    
    private func saveSelectedState() {
        let defaults = UserDefaults.standard
        for filter in filterLists {
            defaults.set(filter.isSelected, forKey: "filter_\(filter.name)")
        }
    }
    
    /// Checks if selected filters exist, downloads if missing
    func checkAndEnableFilters() {
        missingFilters.removeAll()
        for filter in filterLists where filter.isSelected {
            if !filterFileExists(filter) {
                missingFilters.append(filter)
            }
        }
        if !missingFilters.isEmpty {
            DispatchQueue.main.async {
                self.showMissingFiltersSheet = true
            }
        } else {
            Task {
                await applyChanges()
            }
        }
    }
        
    /// Checks if a filter file exists locally
    private func filterFileExists(_ filter: FilterList) -> Bool {
        guard let containerURL = getSharedContainerURL() else { return false }
        let fileURL = containerURL.appendingPathComponent("\(filter.name).json")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    func applyChanges() async {
        showProgressView = true
        isUpdating = true
        progress = 0

        let selectedFilters = filterLists.filter { $0.isSelected }
        let totalSteps = Float(selectedFilters.count)
        var completedSteps: Float = 0

        var allRules: [[String: Any]] = []
        var advancedRules: [[String: Any]] = []

        for filter in selectedFilters {
            if !filterFileExists(filter) {
                let success = await fetchAndProcessFilter(filter)
                if !success {
                    appendLog("Failed to fetch and process filter: \(filter.name)")
                    continue
                }
            }

            if let (rules, advanced) = loadFilterRules(for: filter) {
                allRules.append(contentsOf: rules)
                if let advanced = advanced {
                    advancedRules.append(contentsOf: advanced)
                }
            }

            completedSteps += 1
            progress = completedSteps / totalSteps
        }

        saveBlockerList(allRules)
        saveAdvancedBlockerList(advancedRules)
        await reloadContentBlocker()

        DispatchQueue.main.async {
            self.hasUnappliedChanges = false
            self.isUpdating = false
            self.showProgressView = false
        }
    }
    
    private func loadFilterRules(for filter: FilterList) -> ([[String: Any]], [[String: Any]]?)? {
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
            appendLog("Error loading rules for \(filter.name): \(error)")
            return nil
        }
    }

    private func saveBlockerList(_ rules: [[String: Any]]) {
        do {
            if let jsonData = try? JSONSerialization.data(withJSONObject: rules, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                try FileStorage.shared.saveJSON(jsonString, filename: "blockerList.json")

                // Only store the state in UserDefaults
                if let containerDefaults = UserDefaults(suiteName: sharedContainerIdentifier) {
                    containerDefaults.set(true, forKey: "blockerList")
                    containerDefaults.synchronize()
                }

                appendLog("Successfully saved blockerList to file storage")
            } else {
                appendLog("Error: Unable to serialize blockerList JSON data")
            }
        } catch {
            appendLog("Error saving blockerList: \(error)")
        }
    }

    private func saveAdvancedBlockerList(_ rules: [[String: Any]]) {
        do {
            if let jsonData = try? JSONSerialization.data(withJSONObject: rules, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                try FileStorage.shared.saveJSON(jsonString, filename: "advancedBlocking.json")

                // Only store the state in UserDefaults
                if let containerDefaults = UserDefaults(suiteName: sharedContainerIdentifier) {
                    containerDefaults.set(true, forKey: "advancedBlocking")
                    containerDefaults.synchronize()
                }

                appendLog("Successfully saved advancedBlocking to file storage")
            } else {
                appendLog("Error: Unable to serialize advancedBlocking JSON data")
            }
        } catch {
            appendLog("Error saving advancedBlocking: \(error)")
        }
    }

    
    func updateMissingFilters() async {
        showProgressView = true
        isUpdating = true
        progress = 0
        
        let totalSteps = Float(missingFilters.count)
        var completedSteps: Float = 0
        
        for filter in missingFilters {
            let success = await fetchAndProcessFilter(filter)
            if success {
                missingFilters.removeAll { $0.id == filter.id }
            }
            completedSteps += 1
            progress = completedSteps / totalSteps
        }
        
        await applyChanges()
        isUpdating = false
    }
    
    /// Fetches, processes, and saves a filter list
    private func fetchAndProcessFilter(_ filter: FilterList) async -> Bool {
        do {
            let (data, _) = try await URLSession.shared.data(from: filter.url)
            guard let content = String(data: data, encoding: .utf8) else {
                appendLog("Unable to parse content from \(filter.url)")
                return false
            }
            
            // Save raw content
            if let containerURL = getSharedContainerURL() {
                let rawFileURL = containerURL.appendingPathComponent("\(filter.name).txt")
                try content.write(to: rawFileURL, atomically: true, encoding: .utf8)
            }
            
            let rules = content.components(separatedBy: .newlines)
            let filteredRules = rules.filter { !$0.isEmpty && !$0.hasPrefix("!") && !$0.hasPrefix("[") }
            
            await convertAndSaveRules(filteredRules, for: filter)
            return true
        } catch {
            appendLog("Error fetching filter from \(filter.url): \(error.localizedDescription)")
            return false
        }
    }
    
    /// Converts Adblock rules to Safari-compatible JSON and saves them
    private func convertAndSaveRules(_ rules: [String], for filter: FilterList) async {
        do {
            let converter = ContentBlockerConverter()
            let result = converter.convertArray(
                rules: rules,
                safariVersion: .safari16_4,
                optimize: true,
                advancedBlocking: true
            )
            
            if let containerURL = getSharedContainerURL() {
                let fileURL = containerURL.appendingPathComponent("\(filter.name).json")
                let advancedFileURL = containerURL.appendingPathComponent("\(filter.name)_advanced.json")
                
                if let jsonData = result.converted.data(using: .utf8),
                   var jsonArray = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] {
                    
                    jsonArray = Array(jsonArray.prefix(result.convertedCount))
                    let limitedJsonData = try JSONSerialization.data(withJSONObject: jsonArray, options: .prettyPrinted)
                    
                    try limitedJsonData.write(to: fileURL)
                    appendLog("Successfully wrote \(filter.name).json to: \(fileURL.path)")
                    
                    if let advancedData = result.advancedBlocking?.data(using: .utf8),
                       let advancedArray = try JSONSerialization.jsonObject(with: advancedData, options: []) as? [[String: Any]] {
                        let advancedJsonData = try JSONSerialization.data(withJSONObject: advancedArray, options: .prettyPrinted)
                        try advancedJsonData.write(to: advancedFileURL)
                        appendLog("Successfully wrote \(filter.name)_advanced.json to: \(advancedFileURL.path)")
                    }
                }
            }
        } catch {
            appendLog("ERROR: Failed to convert or save JSON for \(filter.name)")
            appendLog("Error details: \(error.localizedDescription)")
        }
    }
    
    private func enableFilter(_ filter: FilterList) {
        appendLog("Enabling filter: \(filter.name)")
    }
    
    /// Retrieves the shared container URL
    private func getSharedContainerURL() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier)
    }
    
    func reloadContentBlocker() async {
        do {
            let jsonString = try FileStorage.shared.loadJSON(filename: "blockerList.json")
            if let data = jsonString.data(using: .utf8),
               let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                let ruleCount = jsonArray.count
                appendLog("Attempting to reload content blocker with \(ruleCount) rules")

                try await SFContentBlockerManager.reloadContentBlocker(withIdentifier: contentBlockerIdentifier)
                appendLog("Content blocker reloaded successfully with \(ruleCount) rules")
            } else {
                appendLog("Error: Unable to parse blockerList.json")
            }
        } catch {
            appendLog("Error reloading content blocker: \(error)")
        }
    }

    
    func checkAndCreateBlockerList() {
        guard let containerURL = getSharedContainerURL() else {
            appendLog("Error: Unable to access shared container")
            return
        }
        
        let blockerListURL = containerURL.appendingPathComponent("blockerList.json")
        let advancedBlockingURL = containerURL.appendingPathComponent("advancedBlocking.json")
        
        if !FileManager.default.fileExists(atPath: blockerListURL.path) {
            appendLog("blockerList.json not found. Creating it...")
            let selectedFilters = filterLists.filter { $0.isSelected }
            var allRules: [[String: Any]] = []
            var advancedRules: [[String: Any]] = []
            
            for filter in selectedFilters {
                if let (rules, advanced) = loadFilterRules(for: filter) {
                    allRules.append(contentsOf: rules)
                    if let advanced = advanced {
                        advancedRules.append(contentsOf: advanced)
                    }
                }
            }
            
            saveBlockerList(allRules)
            saveAdvancedBlockerList(advancedRules)
        } else {
            appendLog("blockerList.json found.")
        }
    }
    
    func toggleFilterListSelection(id: UUID) {
        if let index = filterLists.firstIndex(where: { $0.id == id }) {
            filterLists[index].isSelected.toggle()
            saveSelectedState()
            hasUnappliedChanges = true
        }
    }
    
    func filterLists(for category: FilterListCategory) -> [FilterList] {
        category == .all ? filterLists : filterLists.filter { $0.category == category }
    }
    
    /// Appends a message to the logs
    func appendLog(_ message: String) {
        logs += message + "\n"
        saveLogsToFile()
    }
    
    /// Saves logs to a file in the shared container
    private func saveLogsToFile() {
        guard let containerURL = getSharedContainerURL() else { return }
        let fileURL = containerURL.appendingPathComponent("logs.txt")
        
        do {
            try logs.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error saving logs: \(error)")
        }
    }
    
    /// Loads logs from the shared container
    func loadLogsFromFile() {
        guard let containerURL = getSharedContainerURL() else { return }
        let fileURL = containerURL.appendingPathComponent("logs.txt")
        
        do {
            logs = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            print("Error loading logs: \(error)")
        }
    }
    
    /// Clears the current logs
    func clearLogs() {
        logs = ""
        saveLogsToFile()
    }
    
    func checkForUpdates() async {
        // Clear the list first
        availableUpdates.removeAll()
        
        // Only check enabled filters
        let enabledFilters = filterLists.filter { $0.isSelected }
        
        for filter in enabledFilters {
            if await hasUpdate(for: filter) {
                availableUpdates.append(filter)
            }
        }
        
        if !availableUpdates.isEmpty {
            DispatchQueue.main.async {
                self.showingUpdatePopup = true
            }
        } else {
            // Show an alert that no updates were found
            DispatchQueue.main.async {
                self.showingNoUpdatesAlert = true
            }
            appendLog("No updates available.")
        }
    }
    
    /// Automatically updates filters and returns the list of updated filters
    func autoUpdateFilters() async -> [FilterList] {
        var updatedFilters: [FilterList] = []
           
        isUpdating = true
        showProgressView = true
        progress = 0
           
        let enabledFilters = filterLists.filter { $0.isSelected }
        let totalSteps = Float(enabledFilters.count)
        var completedSteps: Float = 0
           
        for filter in enabledFilters {
            if await hasUpdate(for: filter) {
                let success = await fetchAndProcessFilter(filter)
                if success {
                    updatedFilters.append(filter)
                }
            }
            completedSteps += 1
            progress = completedSteps / totalSteps
        }
           
        if !updatedFilters.isEmpty {
            await applyChanges()
            appendLog("Applied updates to filters: \(updatedFilters.map { $0.name }.joined(separator: ", "))")
        } else {
            appendLog("No updates found for current filters.")
        }
           
        isUpdating = false
        showProgressView = false
           
        return updatedFilters
    }

    /// Checks if a filter has an update by comparing online content with local content
    private func hasUpdate(for filter: FilterList) async -> Bool {
        guard let containerURL = getSharedContainerURL() else { return false }
        let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
        
        do {
            let (data, _) = try await URLSession.shared.data(from: filter.url)
            let onlineContent = String(data: data, encoding: .utf8) ?? ""
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let localContent = try String(contentsOf: fileURL, encoding: .utf8)
                return onlineContent != localContent
            } else {
                return true // If local file doesn't exist, consider it as needing an update
            }
        } catch {
            appendLog("Error checking update for \(filter.name): \(error.localizedDescription)")
            return false
        }
    }

    func updateSelectedFilters(_ selectedFilters: [FilterList]) async {
        showProgressView = true
        isUpdating = true
        progress = 0
        
        let totalSteps = Float(selectedFilters.count)
        var completedSteps: Float = 0
        
        for filter in selectedFilters {
            let success = await fetchAndProcessFilter(filter)
            if success {
                if let index = availableUpdates.firstIndex(where: { $0.id == filter.id }) {
                    availableUpdates.remove(at: index)
                }
                appendLog("Successfully updated \(filter.name)")
            } else {
                appendLog("Failed to update \(filter.name)")
            }
            completedSteps += 1
            progress = completedSteps / totalSteps
        }
        
        await applyChanges()
        isUpdating = false
        showProgressView = false
    }
    
    func resetToDefaultLists() {
        // Reset all filters to unselected first
        for index in filterLists.indices {
            filterLists[index].isSelected = false
        }
        
        // Enable only the recommended filters
        let recommendedFilters = [
            "AdGuard Base filter",
            "AdGuard Tracking Protection filter",
            "AdGuard Annoyances filter",
            "EasyPrivacy",
            "Online Malicious URL Blocklist",
            "d3Host List byd3ward",
            "Anti-Adblock List"
        ]
        
        for index in filterLists.indices {
            if recommendedFilters.contains(filterLists[index].name) {
                filterLists[index].isSelected = true
            }
        }
        
        saveSelectedState()
        hasUnappliedChanges = true
        appendLog("Reset to default recommended filters")
        
        // Check for missing filters
        checkAndEnableFilters()
    }
    
    // Make sure you're not running the app without filters on!
    func checkForEnabledFilters() {
        let enabledFilters = filterLists.filter { $0.isSelected }
        if enabledFilters.isEmpty {
            showRecommendedFiltersAlert = true
        }
    }

    func enableRecommendedFilters() {
        let recommendedFilters = [
            "AdGuard Base filter",
            "AdGuard Tracking Protection filter",
            "AdGuard Annoyances filter",
            "EasyPrivacy",
            "Online Malicious URL Blocklist",
            "d3Host List by d3ward",
            "Anti-Adblock List"
        ]

        for index in filterLists.indices {
            if recommendedFilters.contains(filterLists[index].name) {
                filterLists[index].isSelected = true
                appendLog("Enabled recommended filter: \(filterLists[index].name)")
            }
        }
        saveSelectedState()
        hasUnappliedChanges = true
        appendLog("Recommended filters have been enabled")
        
        // After enabling recommended filters, check for missing filters
        checkAndEnableFilters()
    }
    
    private func checkAndCreateGroupFolder() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier) else {
            appendLog("Error: Unable to access shared container")
            return
        }
        
        if !FileManager.default.fileExists(atPath: containerURL.path) {
            do {
                try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true, attributes: nil)
                appendLog("Created group folder: \(containerURL.path)")
            } catch {
                appendLog("Error creating group folder: \(error.localizedDescription)")
            }
        } else {
            appendLog("Group folder already exists: \(containerURL.path)")
        }
    }
    
    /// Sends a notification with the latest logs
    func sendLogsAsNotification() async {
        let latestLogs = logs
        let content = UNMutableNotificationContent()
        content.title = "wBlock Logs Updated"
        content.body = "View the latest logs for troubleshooting."
        content.sound = .default
        
        // Add an attachment or additional info if needed
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("Log notification scheduled successfully.")
        } catch {
            print("Failed to schedule log notification: \(error.localizedDescription)")
        }
    }
}

// MARK: - Extensions

extension FilterListManager {
    /// Returns all filters except those in the 'Foreign' category
    func allNonForeignFilters() -> [FilterList] {
        return filterLists.filter { $0.category != .foreign }
    }
       
    /// Returns all filters in the 'Foreign' category
    func foreignFilters() -> [FilterList] {
        return filterLists.filter { $0.category == .foreign }
    }
}
