//
//  AppFilterManager.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI
import Combine
import wBlockCoreService

#if os(macOS)
let APP_CONTENT_BLOCKER_ID = "skula.wBlock.wBlock-Filters"
#else
let APP_CONTENT_BLOCKER_ID = "skula.wBlock.wBlock-Filters-iOS"
#endif

@MainActor
class AppFilterManager: ObservableObject {
    @Published var filterLists: [FilterList] = []
    @Published var isLoading: Bool = false
    @Published var statusDescription: String = "Ready."
    @Published var lastConversionTime: String = "N/A"
    @Published var lastReloadTime: String = "N/A"
    @Published var lastRuleCount: Int = 0
    @Published var hasError: Bool = false
    @Published var progress: Float = 0
    @Published var missingFilters: [FilterList] = []
    @Published var availableUpdates: [FilterList] = []
    @Published var showingUpdatePopup = false
    @Published var showingNoUpdatesAlert = false
    @Published var hasUnappliedChanges = false
    @Published var showMissingFiltersSheet = false
    @Published var showingApplyProgressSheet = false
    @Published var showingDownloadCompleteAlert = false
    @Published var downloadCompleteMessage = ""
    
    // Per-category rule count tracking
    @Published var ruleCountsByCategory: [FilterListCategory: Int] = [:]
    @Published var categoriesApproachingLimit: Set<FilterListCategory> = []
    @Published var showingCategoryWarningAlert = false
    @Published var categoryWarningMessage = ""
    
    // Detailed progress tracking
    @Published var sourceRulesCount: Int = 0
    @Published var conversionStageDescription: String = ""
    @Published var currentFilterName: String = ""
    @Published var processedFiltersCount: Int = 0
    @Published var totalFiltersCount: Int = 0
    @Published var isInConversionPhase: Bool = false
    @Published var isInSavingPhase: Bool = false
    @Published var isInEnginePhase: Bool = false
    @Published var isInReloadPhase: Bool = false
    @Published var currentPlatform: Platform

    // Dependencies
    private let loader: FilterListLoader
    private let updater: FilterListUpdater
    private let logManager: ConcurrentLogManager

    var customFilterLists: [FilterList] = []
    
    // Save filter lists
    func saveFilterLists() {
        loader.saveFilterLists(filterLists) // This will also save the sourceRuleCount if present
    }

    init() {
        self.logManager = ConcurrentLogManager.shared
        self.loader = FilterListLoader(logManager: self.logManager)
        self.updater = FilterListUpdater(loader: self.loader, logManager: self.logManager)
        
        #if os(macOS)
        self.currentPlatform = .macOS
        #else
        self.currentPlatform = .iOS
        #endif
        
        setup()
    }

    private func setup() {
        updater.filterListManager = self
        loader.checkAndCreateGroupFolder()
        filterLists = loader.loadFilterLists()
        customFilterLists = loader.loadCustomFilterLists()
        loader.loadSelectedState(for: &filterLists)
        
        // Load saved rule counts instead of reloading content blockers
        loadSavedRuleCounts()
        
        statusDescription = "Initialized with \(filterLists.count) filter list(s)."
        // Update versions and counts in background without applying changes
        Task { await updateVersionsAndCounts() }
    }
    
    private func loadSavedRuleCounts() {
        // Load last known rule count
        lastRuleCount = UserDefaults.standard.integer(forKey: "lastRuleCount")
        
        // Load category-specific rule counts
        if let data = UserDefaults.standard.data(forKey: "ruleCountsByCategory"),
           let savedCounts = try? JSONDecoder().decode([String: Int].self, from: data) {
            for (key, value) in savedCounts {
                if let category = FilterListCategory(rawValue: key) {
                    ruleCountsByCategory[category] = value
                }
            }
        }
        
        // Load categories approaching limit
        if let data = UserDefaults.standard.data(forKey: "categoriesApproachingLimit"),
           let categoryNames = try? JSONDecoder().decode([String].self, from: data) {
            for name in categoryNames {
                if let category = FilterListCategory(rawValue: name) {
                    categoriesApproachingLimit.insert(category)
                }
            }
        }
    }
    
    private func saveRuleCounts() {
        // Save global rule count
        UserDefaults.standard.set(lastRuleCount, forKey: "lastRuleCount")
        
        // Save category-specific rule counts
        var serializedCounts: [String: Int] = [:]
        for (category, count) in ruleCountsByCategory {
            serializedCounts[category.rawValue] = count
        }
        
        if let data = try? JSONEncoder().encode(serializedCounts) {
            UserDefaults.standard.set(data, forKey: "ruleCountsByCategory")
        }
        
        // Save categories approaching limit
        let categoryNames = categoriesApproachingLimit.map { $0.rawValue }
        if let data = try? JSONEncoder().encode(categoryNames) {
            UserDefaults.standard.set(data, forKey: "categoriesApproachingLimit")
        }
    }
    
    func updateVersionsAndCounts() async {
        let initiallyLoadedLists = self.filterLists
        let updatedListsFromServer = await updater.updateMissingVersionsAndCounts(filterLists: initiallyLoadedLists)
        
        var newFilterLists = self.filterLists
        for updatedListFromServer in updatedListsFromServer {
            if let index = newFilterLists.firstIndex(where: { $0.id == updatedListFromServer.id }) {
                let currentSelectionState = newFilterLists[index].isSelected
                newFilterLists[index] = updatedListFromServer
                newFilterLists[index].isSelected = currentSelectionState
            }
        }
        self.filterLists = newFilterLists
        saveFilterLists()
    }

    func doesFilterFileExist(_ filter: FilterList) -> Bool {
        return loader.filterFileExists(filter)
    }

    // MARK: - Core functionality
    func checkAndEnableFilters(forceReload: Bool = false) {
        missingFilters.removeAll()
        for filter in filterLists where filter.isSelected {
            if !loader.filterFileExists(filter) {
                missingFilters.append(filter)
            }
        }
        if !missingFilters.isEmpty {
            showMissingFiltersSheet = true
        } else if forceReload || hasUnappliedChanges {
            // Only apply changes if explicitly requested or if there are unapplied changes
            showingApplyProgressSheet = true
            Task {
                await applyChanges()
            }
        }
    }

    func toggleFilterListSelection(id: UUID) {
        if let index = filterLists.firstIndex(where: { $0.id == id }) {
            filterLists[index].isSelected.toggle()
            loader.saveSelectedState(for: filterLists)
            hasUnappliedChanges = true
        }
    }

    func filterLists(for category: FilterListCategory) -> [FilterList] {
        category == .all ? filterLists : filterLists.filter { $0.category == category }
    }

    func resetToDefaultLists() {
        // Reset all filters to unselected first
        for index in filterLists.indices {
            filterLists[index].isSelected = false
        }

        // Enable only the recommended filters
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
            if recommendedFilters.contains(filterLists[index].name) {
                filterLists[index].isSelected = true
            }
        }

        loader.saveSelectedState(for: filterLists)
        hasUnappliedChanges = true
    }

    // MARK: - Per-category rule limit management
    
    private func resetCategoryToRecommended(_ category: FilterListCategory) async {
        await ConcurrentLogManager.shared.log("Resetting category \(category.rawValue) to recommended filters due to rule limit exceeded.")
        
        // Define recommended filters per category
        let recommendedFiltersByCategory: [FilterListCategory: [String]] = [
            .ads: ["AdGuard Base Filter"],
            .privacy: ["AdGuard Tracking Protection Filter", "EasyPrivacy"],
            .security: ["Online Malicious URL Blocklist"],
            .annoyances: ["AdGuard Annoyances Filter"],
            .multipurpose: ["d3Host List by d3ward", "Anti-Adblock List"],
            .foreign: [],
            .experimental: [],
            .custom: []
        ]
        
        let recommendedForCategory = recommendedFiltersByCategory[category] ?? []
        
        // Disable all filters in this category first
        for index in filterLists.indices {
            if filterLists[index].category == category {
                filterLists[index].isSelected = false
            }
        }
        
        // Enable only recommended filters for this category
        for index in filterLists.indices {
            if filterLists[index].category == category && recommendedForCategory.contains(filterLists[index].name) {
                filterLists[index].isSelected = true
            }
        }
        
        loader.saveSelectedState(for: filterLists)
        await ConcurrentLogManager.shared.log("Reset category \(category.rawValue) to recommended filters: \(recommendedForCategory.joined(separator: ", "))")
    }
    
    func getCategoryRuleCount(_ category: FilterListCategory) -> Int {
        return ruleCountsByCategory[category] ?? 0
    }
    
    func isCategoryApproachingLimit(_ category: FilterListCategory) -> Bool {
        return categoriesApproachingLimit.contains(category)
    }
    
    func showCategoryWarning(for category: FilterListCategory) {
        let ruleCount = getCategoryRuleCount(category)
        let ruleLimit = currentPlatform == .iOS ? 50000 : 150000
        let warningThreshold = Int(Double(ruleLimit) * 0.8) // 80% threshold
        
        categoryWarningMessage = """
        Category "\(category.rawValue)" is approaching its rule limit:
        
        Current rules: \(ruleCount.formatted())
        Limit: \(ruleLimit.formatted())
        Warning threshold: \(warningThreshold.formatted())
        
        When this category exceeds \(ruleLimit.formatted()) rules, it will be automatically reset to recommended filters only to stay within Safari's content blocker limits.
        """
        
        showingCategoryWarningAlert = true
    }

    // MARK: - Delegated methods

    func applyChanges() async {
        // Update UI state on main thread
        await MainActor.run {
            isLoading = true
            hasError = false
            progress = 0
            statusDescription = "Preparing to apply selected filters..."
            sourceRulesCount = 0
            conversionStageDescription = ""
            currentFilterName = ""
            processedFiltersCount = 0
            self.totalFiltersCount = 0
            isInConversionPhase = false
            isInSavingPhase = false
            isInEnginePhase = false
            isInReloadPhase = false
        }
        
        // Give the UI a chance to update before starting heavy operations
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms delay
        
        await ConcurrentLogManager.shared.log("ApplyChanges: Started on \(currentPlatform == .macOS ? "macOS" : "iOS").")

        let allSelectedFilters = await MainActor.run { filterLists.filter { $0.isSelected } }

        if allSelectedFilters.isEmpty {
            await MainActor.run {
                statusDescription = "No filter lists selected. Clearing rules from all extensions."
            }
            await ConcurrentLogManager.shared.log("ApplyChanges: No filters selected. Clearing all target extensions and filter engine.")
            
            // Perform heavy operations on background thread
            await Task.detached(priority: .userInitiated) {
                // Clear the filter engine when no filters are selected
                ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)
                
                // Clear rules for all relevant extensions
                let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: await MainActor.run { self.currentPlatform })
                for targetInfo in platformTargets {
                    _ = ContentBlockerService.convertFilter(rules: "[]", groupIdentifier: GroupIdentifier.shared.value, targetRulesFilename: targetInfo.rulesFilename).safariRulesCount
                    _ = ContentBlockerService.reloadContentBlocker(withIdentifier: targetInfo.bundleIdentifier)
                }
            }.value
            
            await MainActor.run {
                isLoading = false
                showingApplyProgressSheet = false
                hasUnappliedChanges = false
                lastRuleCount = 0
            }
            return
        }
        
        // Perform heavy file operations on background thread
        let (rulesByTargetInfo, sourceRulesByTargetInfo, totalFiltersCount) = await Task.detached(priority: .userInitiated) {
            // Group filters by their target ContentBlockerTargetInfo
            var rulesByTargetInfo: [ContentBlockerTargetInfo: String] = [:]
            var sourceRulesByTargetInfo: [ContentBlockerTargetInfo: Int] = [:]
            let currentPlatform = await MainActor.run { self.currentPlatform }
            let loader = await MainActor.run { self.loader }

            for filter in allSelectedFilters {
                guard let targetInfo = ContentBlockerTargetManager.shared.targetInfo(forCategory: filter.category, platform: currentPlatform) else {
                    await ConcurrentLogManager.shared.log("Warning: No target extension found for category \(filter.category.rawValue) on \(currentPlatform == .macOS ? "macOS" : "iOS"). Skipping filter: \(filter.name)")
                    continue
                }

                guard let containerURL = loader.getSharedContainerURL() else {
                    await MainActor.run {
                        self.statusDescription = "Error: Unable to access shared container for \(filter.name)"
                        self.hasError = true
                    }
                    continue
                }
                
                let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
                var contentToAppend = ""
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    do {
                        contentToAppend = try String(contentsOf: fileURL, encoding: .utf8) + "\n"
                    } catch {
                        await ConcurrentLogManager.shared.log("Error reading \(filter.name): \(error)")
                    }
                } else {
                    await ConcurrentLogManager.shared.log("Warning: Filter file for \(filter.name) not found locally.")
                }
                
                rulesByTargetInfo[targetInfo, default: ""] += contentToAppend
                sourceRulesByTargetInfo[targetInfo, default: 0] += filter.sourceRuleCount ?? contentToAppend.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("!") && !$0.hasPrefix("[") }.count
            }
            
            let totalFiltersCount = rulesByTargetInfo.keys.count // Number of unique extensions to process
            return (rulesByTargetInfo, sourceRulesByTargetInfo, totalFiltersCount)
        }.value
        
        // Update UI with the calculated values
        await MainActor.run {
            sourceRulesCount = sourceRulesByTargetInfo.values.reduce(0, +) // Sum of all source rules for UI
            self.totalFiltersCount = totalFiltersCount
        }

        if totalFiltersCount == 0 {
            await MainActor.run {
                statusDescription = "No matching extensions for selected filters."
                isLoading = false
                showingApplyProgressSheet = false
            }
            return
        }
        
        var overallSafariRulesApplied = 0
        let overallConversionStartTime = Date()
        var _processedFiltersCount = 0 // Use local variable for background thread

        // Collect all advanced rules from all targets to build the engine once
        var allAdvancedRules: [String] = []
        var advancedRulesByTarget: [String: String] = [:] // Track advanced rules by target bundle ID

        await MainActor.run { isInConversionPhase = true }
        
        for (targetInfo, rulesString) in rulesByTargetInfo {
            _processedFiltersCount += 1
            
            // Update UI on main thread
            await MainActor.run {
                processedFiltersCount = _processedFiltersCount
                progress = Float(processedFiltersCount) / Float(totalFiltersCount) * 0.7 // Up to 70% for conversion
                currentFilterName = targetInfo.primaryCategory.rawValue // More user-friendly
                conversionStageDescription = "Converting \(targetInfo.primaryCategory.rawValue)..."
            }
            
            await ConcurrentLogManager.shared.log("ApplyChanges: Converting rules for \(targetInfo.bundleIdentifier) (\(targetInfo.rulesFilename)). Source lines: \(rulesString.components(separatedBy: .newlines).count)")
            
            try? await Task.sleep(nanoseconds: 50_000_000) // UI update chance

            // Perform heavy conversion on background thread
            let conversionResult = await Task.detached(priority: .userInitiated) {
                ContentBlockerService.convertFilter(
                    rules: rulesString.isEmpty ? "[]" : rulesString, // Ensure "[]" for empty
                    groupIdentifier: GroupIdentifier.shared.value,
                    targetRulesFilename: targetInfo.rulesFilename
                )
            }.value
            
            let ruleCountForThisTarget = conversionResult.safariRulesCount
            overallSafariRulesApplied += ruleCountForThisTarget
            
            // Collect advanced rules for later engine building
            if let advancedRulesText = conversionResult.advancedRulesText, !advancedRulesText.isEmpty {
                allAdvancedRules.append(advancedRulesText)
                advancedRulesByTarget[targetInfo.bundleIdentifier] = advancedRulesText
                await ConcurrentLogManager.shared.log("ApplyChanges: Collected \(advancedRulesText.count) characters of advanced rules from \(targetInfo.bundleIdentifier).")
            }
            
            await ConcurrentLogManager.shared.log("ApplyChanges: Converted \(ruleCountForThisTarget) Safari rules for \(targetInfo.bundleIdentifier).")

            // Update per-category rule count on main thread
            await MainActor.run {
                self.ruleCountsByCategory[targetInfo.primaryCategory] = ruleCountForThisTarget
                if let secondaryCategory = targetInfo.secondaryCategory {
                    self.ruleCountsByCategory[secondaryCategory] = ruleCountForThisTarget
                }
            }

            let currentPlatform = await MainActor.run { self.currentPlatform }
            let ruleLimit = currentPlatform == .iOS ? 50000 : 150000
            let warningThreshold = currentPlatform == .iOS ? 48000 : 140000
            
            // Check if this category is approaching the limit
            await MainActor.run {
                if ruleCountForThisTarget >= warningThreshold && ruleCountForThisTarget < ruleLimit {
                    self.categoriesApproachingLimit.insert(targetInfo.primaryCategory)
                    if let secondaryCategory = targetInfo.secondaryCategory {
                        self.categoriesApproachingLimit.insert(secondaryCategory)
                    }
                } else {
                    self.categoriesApproachingLimit.remove(targetInfo.primaryCategory)
                    if let secondaryCategory = targetInfo.secondaryCategory {
                        self.categoriesApproachingLimit.remove(secondaryCategory)
                    }
                }
            }
            
            if ruleCountForThisTarget > ruleLimit {
                await ConcurrentLogManager.shared.log("CRITICAL: Rule limit \(ruleLimit) exceeded for \(targetInfo.bundleIdentifier) with \(ruleCountForThisTarget) rules.")
                
                // Auto-reset this specific category instead of showing global alert
                await resetCategoryToRecommended(targetInfo.primaryCategory)
                if let secondaryCategory = targetInfo.secondaryCategory {
                    await resetCategoryToRecommended(secondaryCategory)
                }
                
                await MainActor.run {
                    statusDescription = "Auto-reset \(targetInfo.primaryCategory.rawValue) filters due to rule limit exceeded (\(ruleCountForThisTarget)/\(ruleLimit)). Continuing with other categories..."
                }
                await ConcurrentLogManager.shared.log("Auto-reset category \(targetInfo.primaryCategory.rawValue) due to rule limit exceeded.")
                
                // Re-process this target with the reset filters on background thread
                let resetResult = await Task.detached(priority: .userInitiated) {
                    let resetFiltersForCategory = allSelectedFilters.filter { 
                        $0.category == targetInfo.primaryCategory || 
                        (targetInfo.secondaryCategory != nil && $0.category == targetInfo.secondaryCategory!)
                    }
                    
                    var resetRulesString = ""
                    let loader = await MainActor.run { self.loader }
                    for filter in resetFiltersForCategory {
                        if filter.isSelected {
                            guard let containerURL = loader.getSharedContainerURL() else { continue }
                            let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
                            if FileManager.default.fileExists(atPath: fileURL.path) {
                                do {
                                    resetRulesString += try String(contentsOf: fileURL, encoding: .utf8) + "\n"
                                } catch {
                                    await ConcurrentLogManager.shared.log("Error reading \(filter.name) after reset: \(error)")
                                }
                            }
                        }
                    }
                    
                    let resetConversionResult = ContentBlockerService.convertFilter(
                        rules: resetRulesString.isEmpty ? "[]" : resetRulesString,
                        groupIdentifier: GroupIdentifier.shared.value,
                        targetRulesFilename: targetInfo.rulesFilename
                    )
                    
                    return resetConversionResult
                }.value
                
                let resetRuleCount = resetResult.safariRulesCount
                
                // Also collect advanced rules from reset filters
                if let resetAdvancedRulesText = resetResult.advancedRulesText, !resetAdvancedRulesText.isEmpty {
                    // Update the advanced rules for this specific target
                    if let existingIndex = allAdvancedRules.firstIndex(where: { $0 == advancedRulesByTarget[targetInfo.bundleIdentifier] }) {
                        allAdvancedRules[existingIndex] = resetAdvancedRulesText
                    } else {
                        allAdvancedRules.append(resetAdvancedRulesText)
                    }
                    advancedRulesByTarget[targetInfo.bundleIdentifier] = resetAdvancedRulesText
                    await ConcurrentLogManager.shared.log("ApplyChanges: Updated advanced rules after reset for \(targetInfo.bundleIdentifier).")
                } else {
                    // Remove advanced rules for this target if reset resulted in none
                    if let existingAdvancedRules = advancedRulesByTarget[targetInfo.bundleIdentifier],
                       let existingIndex = allAdvancedRules.firstIndex(of: existingAdvancedRules) {
                        allAdvancedRules.remove(at: existingIndex)
                        advancedRulesByTarget.removeValue(forKey: targetInfo.bundleIdentifier)
                        await ConcurrentLogManager.shared.log("ApplyChanges: Removed advanced rules after reset for \(targetInfo.bundleIdentifier).")
                    }
                }
                
                await MainActor.run {
                    self.ruleCountsByCategory[targetInfo.primaryCategory] = resetRuleCount
                    if let secondaryCategory = targetInfo.secondaryCategory {
                        self.ruleCountsByCategory[secondaryCategory] = resetRuleCount
                    }
                    self.categoriesApproachingLimit.remove(targetInfo.primaryCategory)
                    if let secondaryCategory = targetInfo.secondaryCategory {
                        self.categoriesApproachingLimit.remove(secondaryCategory)
                    }
                }
                
                overallSafariRulesApplied += resetRuleCount
                await ConcurrentLogManager.shared.log("ApplyChanges: After reset, \(targetInfo.primaryCategory.rawValue) now has \(resetRuleCount) rules.")
                continue
            }
        }
        await MainActor.run { isInConversionPhase = false }
        
        // Build the combined filter engine with all collected advanced rules on background thread
        if !allAdvancedRules.isEmpty {
            await MainActor.run {
                conversionStageDescription = "Building combined filter engine..."
            }
            await ConcurrentLogManager.shared.log("ApplyChanges: Building filter engine with \(allAdvancedRules.count) groups of advanced rules.")
            
            await Task.detached(priority: .userInitiated) {
                let combinedAdvancedRules = allAdvancedRules.joined(separator: "\n")
                let totalLines = combinedAdvancedRules.components(separatedBy: "\n").count
                await ConcurrentLogManager.shared.log("ApplyChanges: Combined advanced rules: \(combinedAdvancedRules.count) characters, \(totalLines) lines from \(allAdvancedRules.count) filter groups.")
                
                ContentBlockerService.buildCombinedFilterEngine(
                    combinedAdvancedRules: combinedAdvancedRules,
                    groupIdentifier: GroupIdentifier.shared.value
                )
                
                await ConcurrentLogManager.shared.log("ApplyChanges: Successfully built combined filter engine with all advanced rules from \(allAdvancedRules.count) groups.")
            }.value
        } else {
            await ConcurrentLogManager.shared.log("ApplyChanges: No advanced rules found, clearing filter engine.")
            await Task.detached(priority: .userInitiated) {
                ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)
            }.value
        }
        
        // Update UI with conversion results
        await MainActor.run {
            lastRuleCount = overallSafariRulesApplied
            lastConversionTime = String(format: "%.2fs", Date().timeIntervalSince(overallConversionStartTime))
            progress = 0.7
        }
        await ConcurrentLogManager.shared.log("ApplyChanges: All conversions finished. Total Safari rules: \(overallSafariRulesApplied). Time: \(lastConversionTime)")

        // Reloading phase
        await MainActor.run {
            conversionStageDescription = "Reloading Safari extensions..."
            isInReloadPhase = true
        }
        let overallReloadStartTime = Date()
        var allReloadsSuccessful = true
        
        _processedFiltersCount = 0
        for targetInfo in rulesByTargetInfo.keys { // Reload only affected targets
            _processedFiltersCount += 1
            
            // Update UI on main thread
            await MainActor.run {
                processedFiltersCount = _processedFiltersCount
                progress = 0.7 + (Float(processedFiltersCount) / Float(totalFiltersCount) * 0.3) // 70% to 100%
                currentFilterName = targetInfo.primaryCategory.rawValue
            }
            await ConcurrentLogManager.shared.log("ApplyChanges: Reloading \(targetInfo.bundleIdentifier)...")

            // Perform reload on background thread
            let reloadResult = await Task.detached(priority: .userInitiated) {
                ContentBlockerService.reloadContentBlocker(withIdentifier: targetInfo.bundleIdentifier)
            }.value
            
            if case .failure(let error) = reloadResult {
                allReloadsSuccessful = false
                await ConcurrentLogManager.shared.log("ApplyChanges: FAILED to reload \(targetInfo.bundleIdentifier): \(error.localizedDescription)")
                await MainActor.run {
                    if !hasError { statusDescription = "Failed to reload \(targetInfo.primaryCategory.rawValue) extension." }
                    hasError = true // Mark that at least one error occurred
                }
            } else {
                 await ConcurrentLogManager.shared.log("ApplyChanges: Successfully reloaded \(targetInfo.bundleIdentifier).")
            }
            try? await Task.sleep(nanoseconds: 20_000_000) // Small delay
        }
        
        // Reload any other extensions that might have had their rules implicitly cleared (if no selected filters mapped to them)
        let allPlatformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: await MainActor.run { currentPlatform })
        let affectedTargetBundleIDs = Set(rulesByTargetInfo.keys.map { $0.bundleIdentifier })
        
        await Task.detached(priority: .userInitiated) {
            for targetInfo in allPlatformTargets {
                if !affectedTargetBundleIDs.contains(targetInfo.bundleIdentifier) {
                     await ConcurrentLogManager.shared.log("ApplyChanges: Ensuring \(targetInfo.bundleIdentifier) (no selected rules) is also reloaded to apply empty list.")
                     _ = ContentBlockerService.convertFilter(rules: "[]", groupIdentifier: GroupIdentifier.shared.value, targetRulesFilename: targetInfo.rulesFilename).safariRulesCount // Ensure it has an empty list
                     _ = ContentBlockerService.reloadContentBlocker(withIdentifier: targetInfo.bundleIdentifier)
                }
            }
        }.value

        // Update UI with final results
        await MainActor.run {
            isInReloadPhase = false
            lastReloadTime = String(format: "%.2fs", Date().timeIntervalSince(overallReloadStartTime))
            progress = 1.0
        }
        await ConcurrentLogManager.shared.log("ApplyChanges: All reloads finished. Time: \(await MainActor.run { lastReloadTime }). All successful: \(allReloadsSuccessful)")

        // Update final UI state on main thread
        await MainActor.run {
            if allReloadsSuccessful && !hasError {
                conversionStageDescription = "Process completed successfully!"
                statusDescription = "Applied rules to \(rulesByTargetInfo.keys.count) blocker(s). Total: \(overallSafariRulesApplied) Safari rules."
                hasUnappliedChanges = false
            } else if !hasError { // Implies reload issue was the only problem
                statusDescription = "Converted rules, but one or more extensions failed to reload."
            } // If hasError was already true, statusDescription would reflect the earlier error.

            isLoading = false
            // Keep showingApplyProgressSheet = true until user dismisses it if it was successful or had errors.
            // Or: showingApplyProgressSheet = false // if you want it to auto-dismiss on error
        }

        saveFilterLists() // Save any state like sourceRuleCount if updated
        
        // Save rule counts to UserDefaults for next app launch
        saveRuleCounts()
        
        await ConcurrentLogManager.shared.log("ApplyChanges: Finished. Final Status: \(await MainActor.run { statusDescription })")
    }

    func updateMissingFilters() async { // This is for when the "Missing Filters" sheet is shown
        isLoading = true
        progress = 0

        let totalSteps = Float(missingFilters.count)
        var completedSteps: Float = 0
        let tempMissingFilters = self.missingFilters // Work on a temporary copy

        for filter in tempMissingFilters {
            let success = await updater.fetchAndProcessFilter(filter) // This now updates sourceRuleCount
            if success {
                // If successful, the filterListManager?.filterLists is updated by fetchAndProcessFilter
                // We should remove it from our local 'missingFilters' tracking state
                await MainActor.run {
                    self.missingFilters.removeAll { $0.id == filter.id }
                }
            }
            completedSteps += 1
            await MainActor.run {
                self.progress = completedSteps / totalSteps
            }
        }
        
        saveFilterLists() // Save lists as fetchAndProcessFilter might have updated counts/versions

        // Show apply progress sheet for the subsequent apply operation
        await MainActor.run {
            showingApplyProgressSheet = true
        }
        
        await applyChanges()
        isLoading = false
        progress = 0 // Reset progress after completion
    }

    func checkForUpdates() async {
        isLoading = true
        statusDescription = "Checking for updates..."
        // Ensure counts are up-to-date before checking for updates
        await updateVersionsAndCounts()
        
        let enabledFilters = filterLists.filter { $0.isSelected }
        let updatedFilters = await updater.checkForUpdates(filterLists: enabledFilters)

        availableUpdates = updatedFilters

        if !availableUpdates.isEmpty {
            showingUpdatePopup = true
            statusDescription = "Found \(availableUpdates.count) update(s) available."
        } else {
            showingNoUpdatesAlert = true
            statusDescription = "No updates available."
            Task { await ConcurrentLogManager.shared.log("No updates available.") }
        }
        
        isLoading = false
    }

    func autoUpdateFilters() async -> [FilterList] {
        isLoading = true
        progress = 0
        
        // Ensure counts and versions are fresh before auto-update logic
        await updateVersionsAndCounts()

        let updatedFilters = await updater.autoUpdateFilters(
            filterLists: filterLists.filter { $0.isSelected },
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )
        
        saveFilterLists() // Save lists as autoUpdateFilters calls fetchAndProcessFilter

        if !updatedFilters.isEmpty {
            await applyChanges()
        }

        isLoading = false
        progress = 0 // Reset progress after completion
        return updatedFilters
    }

    func updateSelectedFilters(_ selectedFilters: [FilterList]) async { // From UpdatePopupView
        isLoading = true
        progress = 0

        let updatedSuccessfullyFilters = await updater.updateSelectedFilters(
            selectedFilters,
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )
        
        await MainActor.run {
            for filter in updatedSuccessfullyFilters {
                 self.availableUpdates.removeAll { $0.id == filter.id }
            }
        }
        
        saveFilterLists()

        await applyChanges()
        isLoading = false
        progress = 0
    }

    func downloadSelectedFilters(_ selectedFilters: [FilterList]) async {
        isLoading = true
        progress = 0
        statusDescription = "Downloading filter updates..."

        let successfullyUpdatedFilters = await updater.updateSelectedFilters(
            selectedFilters,
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )
        
        saveFilterLists()
        
        await MainActor.run {
            for filter in successfullyUpdatedFilters {
                self.availableUpdates.removeAll { $0.id == filter.id }
            }
        }

        isLoading = false
        progress = 0
        
        await MainActor.run {
            showingUpdatePopup = false
            downloadCompleteMessage = "Downloaded \(successfullyUpdatedFilters.count) filter update(s). Would you like to apply them now?"
            showingDownloadCompleteAlert = true
        }
    }
    
    func downloadMissingFilters() async {
        isLoading = true
        progress = 0
        statusDescription = "Downloading missing filters..."

        let totalSteps = Float(missingFilters.count)
        var completedSteps: Float = 0
        var downloadedCount = 0
        
        let tempMissingFilters = self.missingFilters

        for filter in tempMissingFilters {
            let success = await updater.fetchAndProcessFilter(filter)
            if success {
                await MainActor.run {
                    self.missingFilters.removeAll { $0.id == filter.id }
                }
                downloadedCount += 1
            }
            completedSteps += 1
            await MainActor.run {
                self.progress = completedSteps / totalSteps
            }
        }
        
        saveFilterLists()

        isLoading = false
        progress = 0
        
        await MainActor.run {
            showMissingFiltersSheet = false
            downloadCompleteMessage = "Downloaded \(downloadedCount) missing filter(s). Would you like to apply them now?"
            showingDownloadCompleteAlert = true
        }
    }
    
    func applyDownloadedChanges() async {
        await MainActor.run {
            showingApplyProgressSheet = true
        }
        await applyChanges()
    }

    // MARK: - List Management
    func addFilterList(name: String, urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusDescription = "Invalid URL provided: \(urlString)"
            hasError = true
            Task { await ConcurrentLogManager.shared.log("Error: Invalid URL provided for new filter list - \(urlString)") }
            return
        }
        
        if filterLists.contains(where: { $0.url == url }) {
            statusDescription = "Filter list with this URL already exists: \(url.absoluteString)"
            hasError = true
            Task { await ConcurrentLogManager.shared.log("Error: Filter list with URL \(url.absoluteString) already exists.") }
            return
        }
        
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newFilter = FilterList(id: UUID(),
                                   name: newName.isEmpty ? (url.host ?? "Custom Filter") : newName,
                                   url: url,
                                   category: FilterListCategory.custom,
                                   isSelected: true,
                                   description: "User-added filter list.",
                                   sourceRuleCount: nil)
        addCustomFilterList(newFilter)
    }
    
    func removeFilterList(at offsets: IndexSet) {
        let removedNames = offsets.map { filterLists[$0].name }.joined(separator: ", ")
        filterLists.remove(atOffsets: offsets)
        loader.saveFilterLists(filterLists)
        statusDescription = "Removed filter(s): \(removedNames)"
        hasError = false
        Task { await ConcurrentLogManager.shared.log("Removed filter(s) at offsets: \(removedNames)") }
    }
    
    func removeFilterList(_ listToRemove: FilterList) {
        removeCustomFilterList(listToRemove)
    }

    func toggleFilter(list: FilterList) {
        toggleFilterListSelection(id: list.id)
    }

    func addCustomFilterList(_ filter: FilterList) {
        if !customFilterLists.contains(where: { $0.url == filter.url }) {
            let newFilterToAdd = filter

            customFilterLists.append(newFilterToAdd)
            loader.saveCustomFilterLists(customFilterLists)

            filterLists.append(newFilterToAdd)
            
            Task {
                await ConcurrentLogManager.shared.log("Added custom filter: \(newFilterToAdd.name)")
            }

            Task {
                let success = await updater.fetchAndProcessFilter(newFilterToAdd)
                if success {
                    await ConcurrentLogManager.shared.log("Successfully downloaded custom filter: \(newFilterToAdd.name)")
                    hasUnappliedChanges = true
                    saveFilterLists()
                } else {
                    await ConcurrentLogManager.shared.log("Failed to download custom filter: \(newFilterToAdd.name)")
                    await MainActor.run {
                        removeCustomFilterList(newFilterToAdd)
                    }
                }
            }
        } else {
            Task {
                await ConcurrentLogManager.shared.log("Custom filter with URL \(filter.url) already exists")
            }
        }
    }

    func removeCustomFilterList(_ filter: FilterList) {
        customFilterLists.removeAll { $0.id == filter.id }
        loader.saveCustomFilterLists(customFilterLists)

        filterLists.removeAll { $0.id == filter.id }
        loader.saveFilterLists(filterLists)

        if let containerURL = loader.getSharedContainerURL() {
            let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
            try? FileManager.default.removeItem(at: fileURL)
        }
        Task {
            await ConcurrentLogManager.shared.log("Removed custom filter: \(filter.name)")
        }
        hasUnappliedChanges = true
    }

    func revertToRecommendedFilters() async {
        for index in filterLists.indices {
            filterLists[index].isSelected = false
        }


        #if os(iOS)
        let essentialFilters = [
            "AdGuard Base Filter"
        ]
        #else
        let essentialFilters = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "EasyPrivacy",
            "Online Malicious URL Blocklist"
        ]
        #endif

        for index in filterLists.indices {
            filterLists[index].isSelected = essentialFilters.contains(filterLists[index].name)
        }

        loader.saveSelectedState(for: filterLists)
        hasUnappliedChanges = false
        statusDescription = "Reverted to essential filters to stay under Safari's 150k rule limit."
        
        await MainActor.run {
            showingApplyProgressSheet = true
        }
        await applyChanges()
    }
}
