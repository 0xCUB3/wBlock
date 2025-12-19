//
//  AppFilterManager.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI
import Combine
import wBlockCoreService
import SafariServices

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
    @Published var missingUserScripts: [UserScript] = []
    @Published var whitelistViewModel = WhitelistViewModel()
    @Published var availableUpdates: [FilterList] = []
    @Published var showingUpdatePopup = false
    @Published var showingNoUpdatesAlert = false
    @Published var hasUnappliedChanges = false
    @Published var showMissingItemsSheet = false
    @Published var showingApplyProgressSheet = false
    @Published var autoDisabledFilters: [FilterList] = [] // Filters auto-disabled due to rule limits
    @Published var showingAutoDisabledAlert = false
    
    // Per-category rule count tracking
    @Published var ruleCountsByCategory: [FilterListCategory: Int] = [:]
    @Published var categoriesApproachingLimit: Set<FilterListCategory> = []
    @Published var showingCategoryWarningAlert = false
    @Published var categoryWarningMessage = ""
    
    // Performance tracking
    @Published var lastFastUpdateTime: String = "N/A"
    @Published var fastUpdateCount: Int = 0

    // New ViewModel-based progress tracking
    @Published var applyProgressViewModel = ApplyChangesViewModel()

    // Legacy progress tracking (kept for backward compatibility)
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
    private(set) var filterUpdater: FilterListUpdater
    private let logManager: ConcurrentLogManager
    private let dataManager = ProtobufDataManager.shared
    
    // Per-site disable tracking
    private var lastKnownDisabledSites: [String] = []
    private var disabledSitesCheckTimer: Timer?

    var customFilterLists: [FilterList] = []
    
    // Save filter lists
    func saveFilterLists() async {
        // Use existing updateFilterLists method from ProtobufDataManager+Extensions
        await dataManager.updateFilterLists(filterLists)
    }
    
    // Synchronous wrapper for non-async contexts
    private func saveFilterListsSync() {
        Task {
            await saveFilterLists()
        }
    }

    init() {
        self.logManager = ConcurrentLogManager.shared
        self.loader = FilterListLoader(logManager: self.logManager)
        self.filterUpdater = FilterListUpdater(loader: self.loader, logManager: self.logManager)
        
        #if os(macOS)
        self.currentPlatform = .macOS
        #else
        self.currentPlatform = .iOS
        #endif
        
        // Wait for ProtobufDataManager to finish loading before setting up
        Task {
            await setupAsync()
        }
    }

    /// Resets the manager to its initial state so onboarding can run again.
    @MainActor
    func resetForOnboarding() async {
        isLoading = true
        statusDescription = "Resetting…"
        hasUnappliedChanges = false
        showingApplyProgressSheet = false
        showingUpdatePopup = false
        missingFilters = []
        availableUpdates = []
        showMissingItemsSheet = false
        ruleCountsByCategory = [:]
        categoriesApproachingLimit = []
        showingCategoryWarningAlert = false
        categoryWarningMessage = ""
        lastRuleCount = 0
        lastFastUpdateTime = "N/A"
        fastUpdateCount = 0
        sourceRulesCount = 0
        conversionStageDescription = ""
        currentFilterName = ""
        processedFiltersCount = 0
        totalFiltersCount = 0
        isInConversionPhase = false
        isInSavingPhase = false
        isInEnginePhase = false
        isInReloadPhase = false

        filterLists = []
        customFilterLists = []

        let defaultLists = loader.loadFilterLists()
        filterLists = defaultLists
        saveFilterListsSync()

        await dataManager.updateRuleCounts(
            lastRuleCount: 0,
            ruleCountsByCategory: [:],
            categoriesApproachingLimit: []
        )

        ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)

        statusDescription = "Ready."
        isLoading = false
    }

    private func setupAsync() async {
        // Wait for ProtobufDataManager to finish loading
        while dataManager.isLoading {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        await MainActor.run {
            setup()
        }
    }

    private func setup() {
        filterUpdater.filterListManager = self

        // Load filter lists from protobuf data manager
        var storedFilterLists = dataManager.getFilterLists()

        // Migrate old AdGuard Annoyances filter to new split filters
        storedFilterLists = migrateOldAnnoyancesFilter(in: storedFilterLists)

        let migratedFilterLists = loader.migrateFilterURLs(in: storedFilterLists)
        filterLists = migratedFilterLists
        customFilterLists = dataManager.getCustomFilterLists()

        // Persist migrated filter URLs to the data store when needed
        if storedFilterLists != migratedFilterLists {
            Task {
                for migrated in migratedFilterLists {
                    if let original = storedFilterLists.first(where: { $0.id == migrated.id }),
                       original.url != migrated.url {
                        await self.dataManager.updateFilterList(migrated)
                    }
                }
            }
        }

        // Only load defaults if truly no data exists (not just during async loading)
        if filterLists.isEmpty && !dataManager.isLoading {
            let defaultLists = loader.loadFilterLists()
            filterLists = defaultLists
            saveFilterListsSync()
        }
        
        // Load saved rule counts from protobuf data
        loadSavedRuleCounts()
        
        // Set up observer for disabled sites changes
        setupDisabledSitesObserver()
        
        statusDescription = "Initialized with \(filterLists.count) filter list(s)."
        // Update versions and counts in background without applying changes
        Task { await updateVersionsAndCounts() }
    }
    
    /// Sets up an observer to automatically rebuild content blockers when disabled sites change
    private func setupDisabledSitesObserver() {
        // Store the last known disabled sites to detect changes
    lastKnownDisabledSites = dataManager.disabledSites
        
        // Use a timer to periodically check for changes in disabled sites
        // This is more reliable than protobuf data notifications across app groups
        // Poll every 5 seconds to reduce main thread load during scrolling
        disabledSitesCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForDisabledSitesChanges()
            }
        }
    }
    
    /// Checks for changes in disabled sites and triggers fast rebuild if needed
    @MainActor
    private func checkForDisabledSitesChanges() async {
        // Reload data to get latest changes from extension
        await dataManager.loadData()
        
        let currentDisabledSites = dataManager.disabledSites
        
        if currentDisabledSites != lastKnownDisabledSites {
            await ConcurrentLogManager.shared.info(.whitelist, "Disabled sites changed, fast rebuilding content blockers", metadata: ["previousCount": "\(lastKnownDisabledSites.count)", "newCount": "\(currentDisabledSites.count)"])
            
            lastKnownDisabledSites = currentDisabledSites
            await MainActor.run { self.whitelistViewModel.loadWhitelistedDomains() }
            
            // Only rebuild if we have applied filters (don't rebuild on startup)
            if !hasUnappliedChanges && lastRuleCount > 0 {
                await fastApplyDisabledSitesChanges()
            }
        }
    }
    
    /// Clean up timer when the object is deallocated
    deinit {
        disabledSitesCheckTimer?.invalidate()
    }

    // MARK: - Migration

    /// Migrates old combined AdGuard Annoyances Filter (filter 14) to the new split filters (18-22).
    private func migrateOldAnnoyancesFilter(in filters: [FilterList]) -> [FilterList] {
        var result = filters
        let oldFilterURL = "14_optimized.txt"

        // Find the old combined Annoyances filter
        guard let oldFilterIndex = result.firstIndex(where: { $0.url.absoluteString.contains(oldFilterURL) }) else {
            return result // No migration needed
        }

        let wasSelected = result[oldFilterIndex].isSelected

        // Remove the old filter
        result.remove(at: oldFilterIndex)

        // Define the new split filters
        let newFilters: [(name: String, url: String, description: String)] = [
            ("AdGuard Cookie Notices", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/18_optimized.txt", "Blocks cookie consent notices on web pages."),
            ("AdGuard Popups", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/19_optimized.txt", "Blocks promotional pop-ups, newsletter sign-ups, and notification requests."),
            ("AdGuard Mobile App Banners", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/20_optimized.txt", "Blocks banners promoting mobile app downloads."),
            ("AdGuard Other Annoyances", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/21_optimized.txt", "Blocks miscellaneous irritating elements not covered by other filters."),
            ("AdGuard Widgets", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/22_optimized.txt", "Blocks third-party widgets, chat assistants, and support widgets.")
        ]

        // Add the new filters (only if they don't already exist)
        for filter in newFilters {
            let alreadyExists = result.contains { $0.url.absoluteString.contains(filter.url) }
            if !alreadyExists {
                let newFilter = FilterList(
                    id: UUID(),
                    name: filter.name,
                    url: URL(string: filter.url)!,
                    category: .annoyances,
                    isSelected: wasSelected,
                    description: filter.description
                )
                result.append(newFilter)
            }
        }

        // Persist the migration to protobuf
        Task {
            await dataManager.updateFilterLists(result)
        }

        return result
    }

    /// Fast rebuild for disabled sites changes only - skips SafariConverterLib conversion
    private func fastApplyDisabledSitesChanges() async {
        await MainActor.run {
            self.isLoading = true
            self.statusDescription = "Updating disabled sites..."
        }
        
        await ConcurrentLogManager.shared.info(.whitelist, "Fast applying disabled sites changes without full conversion", metadata: [:])
        
        // Get all platform targets that need updating
        let currentPlatform = self.currentPlatform
        let platformTargets = await Task.detached {
            ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        }.value
        
        // Fast update each target's JSON files without full conversion
        await MainActor.run {
            self.conversionStageDescription = "Fast updating ignore rules..."
        }
        
        // Capture disabled sites on MainActor
        let disabledSites = dataManager.disabledSites
        
        await Task.detached {
            for targetInfo in platformTargets {
                // Use fast update method that only modifies ignore rules
                _ = ContentBlockerService.fastUpdateDisabledSites(
                    groupIdentifier: GroupIdentifier.shared.value,
                    targetRulesFilename: targetInfo.rulesFilename,
                    disabledSites: disabledSites
                )
            }
        }.value
        
        // Now reload content blockers
        await MainActor.run {
            self.conversionStageDescription = "Reloading extensions..."
        }
        
        let overallReloadStartTime = Date()
        var successCount = 0
        
            for targetInfo in platformTargets {
                // Check if this extension has any rules before reloading
                let rulesCount = self.ruleCountsByCategory[targetInfo.primaryCategory] ?? 0
                if rulesCount > 0 {
                    let reloadSuccess = await reloadContentBlockerWithRetry(targetInfo: targetInfo)
                    if reloadSuccess {
                        successCount += 1
                    }
                    // Small delay between reloads to reduce memory pressure
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                } else {
                    // Skip reload for empty extensions
                    await ConcurrentLogManager.shared.debug(.filterApply, "Skipping reload for empty extension", metadata: ["category": targetInfo.primaryCategory.rawValue])
                }
            }
        
        let reloadTime = String(format: "%.2fs", Date().timeIntervalSince(overallReloadStartTime))
        
        await MainActor.run {
            self.lastReloadTime = reloadTime
            self.lastFastUpdateTime = reloadTime
            self.fastUpdateCount += 1
            self.isLoading = false
            self.conversionStageDescription = ""
            
            if successCount == platformTargets.count {
                self.statusDescription = "✅ Disabled sites updated successfully in \(reloadTime) (fast update #\(self.fastUpdateCount))"
            } else {
                self.statusDescription = "⚠️ Updated \(successCount)/\(platformTargets.count) extensions in \(reloadTime)"
            }
        }
        
        await ConcurrentLogManager.shared.info(.whitelist, "Fast disabled sites update completed", metadata: ["successCount": "\(successCount)", "totalCount": "\(platformTargets.count)", "reloadTime": reloadTime])
    }
    
    private func loadSavedRuleCounts() {
        // Load last known rule count from protobuf data
    lastRuleCount = dataManager.lastRuleCount
        
        // Load category-specific rule counts
    for (categoryKey, count) in dataManager.ruleCountsByCategory {
            if let category = FilterListCategory(rawValue: categoryKey) {
                ruleCountsByCategory[category] = Int(count)
            }
        }
        
        // Load categories approaching limit
    for categoryName in dataManager.categoriesApproachingLimit {
            if let category = FilterListCategory(rawValue: categoryName) {
                categoriesApproachingLimit.insert(category)
            }
        }
    }
    
    private func saveRuleCounts() {
        Task { @MainActor in
            await dataManager.updateRuleCounts(
                lastRuleCount: lastRuleCount,
                ruleCountsByCategory: ruleCountsByCategory,
                categoriesApproachingLimit: categoriesApproachingLimit
            )
        }
    }
    
    func updateVersionsAndCounts() async {
        let initiallyLoadedLists = self.filterLists
        let updatedListsFromServer = await filterUpdater.updateMissingVersionsAndCounts(filterLists: initiallyLoadedLists)

        var newFilterLists = self.filterLists
        for updatedListFromServer in updatedListsFromServer {
            if let index = newFilterLists.firstIndex(where: { $0.id == updatedListFromServer.id }) {
                let currentSelectionState = newFilterLists[index].isSelected
                newFilterLists[index] = updatedListFromServer
                newFilterLists[index].isSelected = currentSelectionState
            }
        }
        self.filterLists = newFilterLists
        saveFilterListsSync()
    }

    /// Updates version and count for a single filter instead of all filters
    func updateSingleFilterVersionAndCount(_ filter: FilterList) async {
        let updatedFilters = await filterUpdater.updateMissingVersionsAndCounts(filterLists: [filter])

        guard let updatedFilter = updatedFilters.first,
              let index = self.filterLists.firstIndex(where: { $0.id == filter.id }) else {
            return
        }

        var newFilterLists = self.filterLists
        let currentSelectionState = newFilterLists[index].isSelected
        newFilterLists[index] = updatedFilter
        newFilterLists[index].isSelected = currentSelectionState
        self.filterLists = newFilterLists
        saveFilterListsSync()
    }

    func doesFilterFileExist(_ filter: FilterList) -> Bool {
        return loader.filterFileExists(filter)
    }

    // MARK: - Core functionality
    func checkAndEnableFilters(forceReload: Bool = false) {
        missingFilters.removeAll()
        missingUserScripts.removeAll()

        // Check for missing filters
        for filter in filterLists where filter.isSelected {
            if !loader.filterFileExists(filter) {
                missingFilters.append(filter)
            }
        }

        // Check for missing userscripts
        if let userScriptManager = filterUpdater.userScriptManager {
            for script in userScriptManager.userScripts where script.isEnabled {
                if !script.isDownloaded {
                    missingUserScripts.append(script)
                }
            }
        }

        if !missingFilters.isEmpty || !missingUserScripts.isEmpty {
            showMissingItemsSheet = true
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

            if filterLists[index].isSelected {
                filterLists[index].limitExceededReason = nil
                autoDisabledFilters.removeAll { $0.id == id }
            }

            saveFilterListsSync()
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
        #if os(iOS)
        let recommendedFilters = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "AdGuard Annoyances Filter",
            "AdGuard Mobile Ads Filter",
            "EasyPrivacy",
            "Online Security Filter",
            "d3Host List by d3ward",
            "Anti-Adblock List"
        ]
        #else
        let recommendedFilters = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "AdGuard Annoyances Filter",
            "EasyPrivacy",
            "Online Security Filter",
            "d3Host List by d3ward",
            "Anti-Adblock List"
        ]
        #endif

        for index in filterLists.indices {
            if recommendedFilters.contains(filterLists[index].name) {
                filterLists[index].isSelected = true
            }
        }

        saveFilterListsSync()
        hasUnappliedChanges = true
    }

    // MARK: - Per-category rule limit management
    
    private func resetCategoryToRecommended(_ category: FilterListCategory) async {
        await ConcurrentLogManager.shared.warning(.filterApply, "Resetting category to recommended filters due to rule limit exceeded", metadata: ["category": category.rawValue])

        let recommendedFiltersByCategory: [FilterListCategory: [String]] = [
            .ads: ["AdGuard Base Filter"],
            .privacy: ["AdGuard Tracking Protection Filter", "EasyPrivacy"],
            .security: ["Online Security Filter"],
            .annoyances: ["AdGuard Annoyances Filter"],
            .multipurpose: ["d3Host List by d3ward", "Anti-Adblock List"],
            .foreign: [],
            .experimental: [],
            .custom: []
        ]

        let recommendedForCategory = recommendedFiltersByCategory[category] ?? []
        var disabledFiltersInCategory: [FilterList] = []

        for index in filterLists.indices {
            if filterLists[index].category == category {
                if filterLists[index].isSelected && !recommendedForCategory.contains(filterLists[index].name) {
                    filterLists[index].limitExceededReason = "Automatically disabled because the '\(category.rawValue)' category exceeded Safari's 150,000 rule limit. To re-enable, disable other filters in this category first."
                    disabledFiltersInCategory.append(filterLists[index])
                }
                filterLists[index].isSelected = false
            }
        }

        for index in filterLists.indices {
            if filterLists[index].category == category && recommendedForCategory.contains(filterLists[index].name) {
                filterLists[index].isSelected = true
                filterLists[index].limitExceededReason = nil
            }
        }

        await MainActor.run {
            self.autoDisabledFilters.removeAll { $0.category == category }
            self.autoDisabledFilters.append(contentsOf: disabledFiltersInCategory)
        }

        loader.saveSelectedState(for: filterLists)
        await ConcurrentLogManager.shared.info(.filterApply, "Reset category to recommended filters", metadata: ["category": category.rawValue, "filters": recommendedForCategory.joined(separator: ", "), "autoDisabled": "\(disabledFiltersInCategory.count)"])
    }
    
    func getCategoryRuleCount(_ category: FilterListCategory) -> Int {
        return ruleCountsByCategory[category] ?? 0
    }
    
    func isCategoryApproachingLimit(_ category: FilterListCategory) -> Bool {
        return categoriesApproachingLimit.contains(category)
    }
    
    func showCategoryWarning(for category: FilterListCategory) {
        let ruleCount = getCategoryRuleCount(category)
        let ruleLimit = 150000
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

    // MARK: - Helper Methods
    
    /// Attempts to reload a content blocker with up to 5 retry attempts
    /// Returns true if successful, false if all attempts failed
    private func reloadContentBlockerWithRetry(targetInfo: ContentBlockerTargetInfo) async -> Bool {
        let maxRetries = 5
        let categoryName = targetInfo.primaryCategory.rawValue
        
        for attempt in 1...maxRetries {
            let result = ContentBlockerService.reloadContentBlocker(withIdentifier: targetInfo.bundleIdentifier)
            if case .success = result {
                if attempt > 1 {
                    await ConcurrentLogManager.shared.info(.filterApply, "Content blocker reloaded successfully after retry", metadata: ["category": categoryName, "attempt": "\(attempt)"])
                }
                return true
            } else if case .failure(let error) = result {
                if attempt == 1 || attempt == maxRetries {
                    await ConcurrentLogManager.shared.error(.filterApply, attempt == maxRetries ? "Content blocker reload failed after all attempts" : "Content blocker reload failed", metadata: ["category": categoryName, "attempt": "\(attempt)", "maxRetries": "\(maxRetries)", "error": error.localizedDescription])
                }
                
                if attempt < maxRetries {
                    let delayMs = attempt * 200
                    if attempt >= 2 {
                        await MainActor.run {
                            self.conversionStageDescription = "Retrying \(categoryName) (attempt \(attempt + 1))..."
                        }
                    }
                    try? await Task.sleep(nanoseconds: UInt64(delayMs * 1_000_000))
                }
            }
        }
        
        return false
    }

    // MARK: - Delegated methods

    func applyChanges() async {
        await MainActor.run {
            self.isLoading = true
            self.hasError = false
            self.progress = 0
            self.statusDescription = "Checking for updates..."

            // Reset and initialize new ViewModel
            self.applyProgressViewModel.reset()
            self.applyProgressViewModel.updateIsLoading(true)
            self.applyProgressViewModel.updateProgress(0)

            // Legacy properties (kept for backward compatibility)
            self.sourceRulesCount = 0
            self.conversionStageDescription = ""
            self.currentFilterName = ""
            self.processedFiltersCount = 0
            self.totalFiltersCount = 0
            self.isInConversionPhase = false
            self.isInSavingPhase = false
            self.isInEnginePhase = false
            self.isInReloadPhase = false
        }

        // Allow the apply progress UI to render fully before heavy work begins.
        let shouldDelayForUI = await MainActor.run { self.showingApplyProgressSheet }
        if shouldDelayForUI {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 120_000_000) // ~0.12s for sheet presentation
        }

        await ConcurrentLogManager.shared.info(.filterApply, "Starting filter application process", metadata: ["platform": currentPlatform == .macOS ? "macOS" : "iOS"])

        // First, check for and download updates for enabled filters
        await MainActor.run {
            self.statusDescription = "Checking for updates..."
            self.applyProgressViewModel.updateStageDescription("Checking for updates...")
            self.applyProgressViewModel.updatePhaseCompletion(updating: false) // Mark as active
        }

        await updateVersionsAndCounts()

        let enabledFilters = await MainActor.run { self.filterLists.filter { $0.isSelected } }
        if !enabledFilters.isEmpty {
            let updatedFilters = await filterUpdater.checkForUpdates(filterLists: enabledFilters)

            await MainActor.run {
                self.applyProgressViewModel.updateUpdatesFound(updatedFilters.count)
            }

            if !updatedFilters.isEmpty {
                await MainActor.run {
                    self.statusDescription = "Downloading \(updatedFilters.count) update(s)..."
                    self.applyProgressViewModel.updateStageDescription("Downloading \(updatedFilters.count) update(s)...")
                }

                await ConcurrentLogManager.shared.info(.filterApply, "Found and downloading updates before applying", metadata: ["count": "\(updatedFilters.count)"])

                _ = await filterUpdater.updateSelectedFilters(updatedFilters, progressCallback: { prog in
                    Task { @MainActor in
                        self.progress = prog * 0.1 // Use first 10% of progress for updates
                        self.applyProgressViewModel.updateProgress(Float(prog * 0.1))
                    }
                })

                saveFilterListsSync()
            } else {
                await ConcurrentLogManager.shared.info(.filterApply, "No updates available", metadata: [:])
            }
        }

        // Mark updating phase as complete
        await MainActor.run {
            self.applyProgressViewModel.updatePhaseCompletion(updating: true, reading: false)
            self.statusDescription = "Applying filters...\n(This may take a while)"
            self.applyProgressViewModel.updateStageDescription("Applying filters...")
        }

        let allSelectedFilters = await MainActor.run { self.filterLists.filter { $0.isSelected } }

        if allSelectedFilters.isEmpty {
            await MainActor.run {
                self.statusDescription = "No filter lists selected. Clearing rules from all extensions."
            }
            await ConcurrentLogManager.shared.info(.filterApply, "No filters selected - clearing all extensions", metadata: [:])
            
            // Perform heavy operations on background thread
            let currentPlatform = self.currentPlatform
            let disabledSites = self.dataManager.disabledSites
            
            await Task.detached {
                // Clear the filter engine when no filters are selected
                ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)
                
                // Clear rules for all relevant extensions
                let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
                for targetInfo in platformTargets {
                    _ = ContentBlockerService.convertFilter(rules: "", groupIdentifier: GroupIdentifier.shared.value, targetRulesFilename: targetInfo.rulesFilename, disabledSites: disabledSites).safariRulesCount
                    await self.reloadContentBlockerWithRetry(targetInfo: targetInfo)
                }
            }.value
            
            await MainActor.run {
                self.isLoading = false
                self.showingApplyProgressSheet = false
                self.hasUnappliedChanges = false
                self.lastRuleCount = 0
            }
            return
        }
        
        // Group filters by their target ContentBlockerTargetInfo - avoid loading everything into memory at once
        var filtersByTargetInfo: [ContentBlockerTargetInfo: [FilterList]] = [:]
        var sourceRulesByTargetInfo: [ContentBlockerTargetInfo: Int] = [:]

        for filter in allSelectedFilters {
            guard let targetInfo = ContentBlockerTargetManager.shared.targetInfo(forCategory: filter.category, platform: self.currentPlatform) else {
                await ConcurrentLogManager.shared.warning(.filterApply, "No target extension found for category, skipping filter", metadata: ["category": filter.category.rawValue, "platform": self.currentPlatform == .macOS ? "macOS" : "iOS", "filter": filter.name])
                continue
            }

            filtersByTargetInfo[targetInfo, default: []].append(filter)
            sourceRulesByTargetInfo[targetInfo, default: 0] += filter.sourceRuleCount ?? 0
        }
        
        let totalFiltersCount = filtersByTargetInfo.keys.count
        await MainActor.run {
            self.sourceRulesCount = sourceRulesByTargetInfo.values.reduce(0, +) // Sum of all source rules for UI
            self.totalFiltersCount = totalFiltersCount // Number of unique extensions to process

            // Update ViewModel
            self.applyProgressViewModel.updateProcessedCount(0, total: totalFiltersCount)
            self.applyProgressViewModel.updateStageDescription("Starting conversion...")
        }

        if totalFiltersCount == 0 {
            await MainActor.run {
                self.statusDescription = "No matching extensions for selected filters."
                self.isLoading = false
                self.showingApplyProgressSheet = false
            }
            return
        }
        
        var overallSafariRulesApplied = 0
        let overallConversionStartTime = Date()
        
        await MainActor.run {
            self.processedFiltersCount = 0 // Use this to track processed targets for progress
            self.isInConversionPhase = true

            // Update ViewModel phase
            self.applyProgressViewModel.updatePhaseCompletion(reading: true, converting: false)
        }

        // Collect advanced rules by target bundle ID (single storage)
        var advancedRulesByTarget: [String: String] = [:] // Track advanced rules by target bundle ID
        for (targetInfo, filters) in filtersByTargetInfo {
            await MainActor.run {
                self.processedFiltersCount += 1
                self.progress = Float(self.processedFiltersCount) / Float(totalFiltersCount) * 0.7 // Up to 70% for conversion
                self.currentFilterName = targetInfo.primaryCategory.rawValue // More user-friendly
                self.conversionStageDescription = "Converting \(targetInfo.primaryCategory.rawValue)..."
                self.isInSavingPhase = true // Set saving phase for each conversion

                // Batched ViewModel update - single call with all data
                self.applyProgressViewModel.updateProgress(self.progress)
                self.applyProgressViewModel.updateCurrentFilter(targetInfo.primaryCategory.rawValue)
                self.applyProgressViewModel.updateProcessedCount(self.processedFiltersCount, total: totalFiltersCount)
                self.applyProgressViewModel.updateStageDescription("Converting \(targetInfo.primaryCategory.rawValue)...")
            }

            // Yield to prevent main thread starvation on iOS
            await Task.yield()

            // Capture disabled sites
            let disabledSites = self.dataManager.disabledSites

            // Efficiently combine rules from multiple files without loading all into memory at once
            let conversionResult = await Task.detached {
                return await self.convertFiltersMemoryEfficient(filters: filters, targetInfo: targetInfo, disabledSites: disabledSites)
            }.value
            
            await MainActor.run {
                self.isInSavingPhase = false // Clear saving phase after conversion
            }
            
            let ruleCountForThisTarget = conversionResult.safariRulesCount
            
            // Store advanced rules for later engine building
            if let advancedRulesText = conversionResult.advancedRulesText, !conversionResult.advancedRulesText!.isEmpty {
                advancedRulesByTarget[targetInfo.bundleIdentifier] = advancedRulesText
            }
            
            // Single consolidated log per target
            let advancedCount = conversionResult.advancedRulesText?.isEmpty == false ? conversionResult.advancedRulesText!.components(separatedBy: .newlines).count : 0
            await ConcurrentLogManager.shared.info(.filterApply, "Converted category rules", metadata: ["category": targetInfo.primaryCategory.rawValue, "safariRules": "\(ruleCountForThisTarget)", "advancedRules": "\(advancedCount)"])
            
            // Update per-category rule count on main thread
            await MainActor.run {
                self.ruleCountsByCategory[targetInfo.primaryCategory] = ruleCountForThisTarget
                if let secondaryCategory = targetInfo.secondaryCategory {
                    self.ruleCountsByCategory[secondaryCategory] = ruleCountForThisTarget
                }
            }

            let ruleLimit = 150000
            let warningThreshold = Int(Double(ruleLimit) * 0.8) // 80% threshold
            
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
                await ConcurrentLogManager.shared.error(.filterApply, "Rule limit exceeded for category", metadata: ["bundleId": targetInfo.bundleIdentifier, "ruleCount": "\(ruleCountForThisTarget)", "ruleLimit": "\(ruleLimit)"])
                
                // Auto-reset this specific category and warn the user
                await resetCategoryToRecommended(targetInfo.primaryCategory)
                if let secondaryCategory = targetInfo.secondaryCategory {
                    await resetCategoryToRecommended(secondaryCategory)
                }

                await MainActor.run {
                    self.showCategoryWarning(for: targetInfo.primaryCategory)
                    self.showingAutoDisabledAlert = true
                }
                await ConcurrentLogManager.shared.info(.filterApply, "Auto-reset category due to rule limit exceeded", metadata: ["category": targetInfo.primaryCategory.rawValue])
                
                // Re-process this target with the reset filters - on background thread
                let disabledSites = self.dataManager.disabledSites
                let resetResult = await Task.detached {
                    let containerURL = await MainActor.run { self.loader.getSharedContainerURL() }
                    var resetRulesString = ""

                    // Get the updated filter list after reset
                    let updatedSelectedFilters = await MainActor.run { self.filterLists.filter { $0.isSelected } }
                    
                    for filter in updatedSelectedFilters {
                        if filter.category == targetInfo.primaryCategory || 
                           (targetInfo.secondaryCategory != nil && filter.category == targetInfo.secondaryCategory!) {
                            guard let containerURL = containerURL else { continue }
                            let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
                            if FileManager.default.fileExists(atPath: fileURL.path) {
                                do {
                                    resetRulesString += try String(contentsOf: fileURL, encoding: .utf8) + "\n"
                                } catch {
                                    await ConcurrentLogManager.shared.error(.filterApply, "Error reading filter after reset", metadata: ["filter": filter.name, "error": "\(error)"])
                                }
                            }
                        }
                    }
                    
                    return ContentBlockerService.convertFilter(
                        rules: resetRulesString.isEmpty ? "[]" : resetRulesString,
                        groupIdentifier: GroupIdentifier.shared.value,
                        targetRulesFilename: targetInfo.rulesFilename,
                        disabledSites: disabledSites
                    )
                }.value
                
                let resetRuleCount = resetResult.safariRulesCount
                
                // Update advanced rules from reset filters
                if let resetAdvancedRulesText = resetResult.advancedRulesText, !resetResult.advancedRulesText!.isEmpty {
                    advancedRulesByTarget[targetInfo.bundleIdentifier] = resetAdvancedRulesText
                } else {
                    // Remove advanced rules for this target if reset resulted in none
                    advancedRulesByTarget.removeValue(forKey: targetInfo.bundleIdentifier)
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
                await ConcurrentLogManager.shared.info(.filterApply, "After reset, category now has fewer rules", metadata: ["category": targetInfo.primaryCategory.rawValue, "ruleCount": "\(resetRuleCount)"])
                continue
            }
            else {
                overallSafariRulesApplied += ruleCountForThisTarget
            }
        }
        await MainActor.run {
            self.isInConversionPhase = false
            self.lastRuleCount = overallSafariRulesApplied
            self.lastConversionTime = String(format: "%.2fs", Date().timeIntervalSince(overallConversionStartTime))
            self.progress = 0.7

            // Update ViewModel - conversion complete
            self.applyProgressViewModel.updateProgress(self.progress)
            self.applyProgressViewModel.updatePhaseCompletion(converting: true, saving: false)
        }
        await ConcurrentLogManager.shared.info(.filterApply, "All conversions finished", metadata: ["totalRules": "\(overallSafariRulesApplied)", "conversionTime": await MainActor.run { self.lastConversionTime }])

        // Reloading phase - reload all content blockers FIRST before building advanced engine
        await MainActor.run {
            self.conversionStageDescription = "Reloading Safari extensions..."
            self.isInReloadPhase = true
            self.processedFiltersCount = 0

            // Update ViewModel - starting reload phase
            self.applyProgressViewModel.updatePhaseCompletion(saving: true, reloading: false)
            self.applyProgressViewModel.updateStageDescription("Reloading Safari extensions...")
        }
        
        let overallReloadStartTime = Date()
        var allReloadsSuccessful = true
        
        for targetInfo in filtersByTargetInfo.keys { // Reload only affected targets
            await MainActor.run {
                self.processedFiltersCount += 1
                self.progress = 0.7 + (Float(self.processedFiltersCount) / Float(totalFiltersCount) * 0.2) // 70% to 90%
                self.currentFilterName = targetInfo.primaryCategory.rawValue

                // Batched ViewModel update
                self.applyProgressViewModel.updateProgress(self.progress)
                self.applyProgressViewModel.updateCurrentFilter(targetInfo.primaryCategory.rawValue)
            }

            // Yield to prevent blocking
            await Task.yield()

            // Reload with retry logic (logging handled in helper function)
            let reloadSuccess = await reloadContentBlockerWithRetry(targetInfo: targetInfo)
            
            // Final result after all attempts
            if !reloadSuccess {
                allReloadsSuccessful = false
                await MainActor.run {
                    if !self.hasError { 
                        self.statusDescription = "Failed to reload \(targetInfo.primaryCategory.rawValue) extension after 5 attempts." 
                    }
                    self.hasError = true
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // Longer delay between reloads to reduce memory pressure
        }
        
        // Reload any other extensions that might have had their rules implicitly cleared (if no selected filters mapped to them)
        let currentPlatform = self.currentPlatform
        let disabledSites = self.dataManager.disabledSites
        
        let allPlatformTargets = await Task.detached {
            ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        }.value
        
        let affectedTargetBundleIDs = Set(filtersByTargetInfo.keys.map { $0.bundleIdentifier })
        
        for targetInfo in allPlatformTargets {
            if !affectedTargetBundleIDs.contains(targetInfo.bundleIdentifier) {
                 // Run conversion and reload on background thread
                 await Task.detached {
                     _ = ContentBlockerService.convertFilter(rules: "", groupIdentifier: GroupIdentifier.shared.value, targetRulesFilename: targetInfo.rulesFilename, disabledSites: disabledSites).safariRulesCount // Ensure it has an empty list
                 }.value
                 
                 let reloadSuccess = await reloadContentBlockerWithRetry(targetInfo: targetInfo)
                 
                 // Final result after all attempts
                 if !reloadSuccess {
                     allReloadsSuccessful = false
                     await MainActor.run {
                         if !self.hasError { 
                             self.statusDescription = "Failed to reload \(targetInfo.primaryCategory.rawValue) extension after 5 attempts." 
                         }
                         self.hasError = true
                     }
                 }
            }
        }
        
        // Log reload summary
        await MainActor.run {
            self.isInReloadPhase = false
            self.lastReloadTime = String(format: "%.2fs", Date().timeIntervalSince(overallReloadStartTime))
        }
        
        if allReloadsSuccessful {
            await ConcurrentLogManager.shared.info(.filterApply, "All content blocker reloads completed successfully", metadata: ["reloadTime": await MainActor.run { self.lastReloadTime }])
        } else {
            await ConcurrentLogManager.shared.warning(.filterApply, "Some content blocker reloads failed after retries, continuing with advanced rules processing", metadata: [:])
        }

        // Small delay before building advanced engine to let system recover from reloads
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
        
        // NOW build the combined filter engine AFTER all content blockers are reloaded
        await MainActor.run {
            self.progress = 0.9

            // Update ViewModel
            self.applyProgressViewModel.updateProgress(self.progress)
            self.applyProgressViewModel.updatePhaseCompletion(reloading: true)
        }
        
        if !advancedRulesByTarget.isEmpty {
            await MainActor.run {
                self.conversionStageDescription = "Building combined filter engine..."
                self.isInEnginePhase = true
            }
            
            // Run engine building on background thread
            await Task.detached {
                let combinedAdvancedRules = advancedRulesByTarget.values.joined(separator: "\n")
                let totalLines = combinedAdvancedRules.components(separatedBy: "\n").count
                await ConcurrentLogManager.shared.info(.filterApply, "Building filter engine", metadata: ["targetCount": "\(advancedRulesByTarget.count)", "totalLines": "\(totalLines)"])
                
                ContentBlockerService.buildCombinedFilterEngine(
                    combinedAdvancedRules: combinedAdvancedRules,
                    groupIdentifier: GroupIdentifier.shared.value
                )
            }.value
            
            await MainActor.run {
                self.isInEnginePhase = false
            }
        } else {
            await ConcurrentLogManager.shared.debug(.filterApply, "No advanced rules found, clearing filter engine", metadata: [:])
            // Run on background thread
            await Task.detached {
                ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)
            }.value
        }
        
        await MainActor.run {
            self.progress = 1.0

            // Update ViewModel to 100%
            self.applyProgressViewModel.updateProgress(1.0)
        }

        let hasErrorValue = await MainActor.run { self.hasError }
        if allReloadsSuccessful && !hasErrorValue {
            await MainActor.run {
                self.conversionStageDescription = "Process completed successfully!"
                self.statusDescription = "Applied rules to \(filtersByTargetInfo.keys.count) blocker(s). Total: \(overallSafariRulesApplied) Safari rules. Advanced engine: \(advancedRulesByTarget.isEmpty ? "cleared" : "\(advancedRulesByTarget.count) targets combined")."
                self.hasUnappliedChanges = false
            }
        } else if !hasErrorValue { // Implies reload issue was the only problem
            await MainActor.run {
                self.conversionStageDescription = "Conversion completed with reload issues"
                self.statusDescription = "Converted rules, but one or more extensions failed to reload after 5 attempts. Advanced engine: \(advancedRulesByTarget.isEmpty ? "cleared" : "\(advancedRulesByTarget.count) targets combined")."
            }
        } // If hasError was already true, statusDescription would reflect the earlier error.

        await MainActor.run {
            self.isLoading = false

            // Update ViewModel with final statistics
            self.applyProgressViewModel.updateStatistics(
                sourceRules: self.sourceRulesCount,
                safariRules: self.lastRuleCount,
                conversionTime: self.lastConversionTime,
                reloadTime: self.lastReloadTime,
                ruleCountsByCategory: self.ruleCountsByCategory,
                categoriesApproachingLimit: self.categoriesApproachingLimit,
                statusMessage: self.statusDescription
            )
            self.applyProgressViewModel.updateIsLoading(false)
        }
        // Keep showingApplyProgressSheet = true until user dismisses it if it was successful or had errors.
        // Or: showingApplyProgressSheet = false // if you want it to auto-dismiss on error

        saveFilterListsSync() // Save any state like sourceRuleCount if updated
        
        // Save rule counts to UserDefaults for next app launch
        saveRuleCounts()
        
        // Final summary log
        let hasErrorValueForLog = await MainActor.run { self.hasError }
        let statusDesc = await MainActor.run { self.statusDescription }
        
        if allReloadsSuccessful && !hasErrorValueForLog {
            await ConcurrentLogManager.shared.info(.filterApply, "Process completed successfully", metadata: ["status": statusDesc])
        } else if !hasErrorValueForLog {
            await ConcurrentLogManager.shared.warning(.filterApply, "Process completed with reload issues", metadata: ["status": statusDesc])
        } else {
            await ConcurrentLogManager.shared.error(.filterApply, "Process completed with errors", metadata: ["status": statusDesc])
        }
    }
    
    @MainActor
    public func downloadAndApplyFilters(filters: [FilterList], progress: @escaping (Float) -> Void) async {
        isLoading = true
        hasError = false
        statusDescription = "Downloading filter lists..."
        progress(0)

        // Download selected filters using existing updater logic
        let _ = await filterUpdater.updateSelectedFilters(filters, progressCallback: { prog in
            Task { @MainActor in
                self.progress = Float(prog)
                progress(Float(prog))
            }
        })

        // Save after download
        saveFilterListsSync()

        // Apply changes (conversion, reload, etc)
        statusDescription = "Applying filters...\n(This may take a while)"
        await applyChanges()

        isLoading = false
        progress(1)
        statusDescription = "Ready."
    }

    func updateMissingFilters() async { // This is for when the "Missing Filters" sheet is shown
        isLoading = true
        progress = 0

        let totalSteps = Float(missingFilters.count)
        var completedSteps: Float = 0
        let tempMissingFilters = self.missingFilters // Work on a temporary copy

        for filter in tempMissingFilters {
            let success = await filterUpdater.fetchAndProcessFilter(filter) // This now updates sourceRuleCount
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
        
        saveFilterListsSync() // Save lists as fetchAndProcessFilter might have updated counts/versions

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
        let updatedFilters = await filterUpdater.checkForUpdates(filterLists: enabledFilters)

        availableUpdates = updatedFilters

        // Also check for userscript updates
        if let userScriptManager = filterUpdater.userScriptManager {
            let downloadedScripts = userScriptManager.userScripts.filter { $0.isDownloaded }
            for script in downloadedScripts {
                await userScriptManager.updateUserScript(script)
            }
        }

        if !availableUpdates.isEmpty {
            showingUpdatePopup = true
            statusDescription = "Found \(availableUpdates.count) update(s) available."
        } else {
            showingNoUpdatesAlert = true
            statusDescription = "No updates available."
            Task { await ConcurrentLogManager.shared.info(.autoUpdate, "No updates available", metadata: [:]) }
        }

        isLoading = false
    }

    func autoUpdateFilters() async -> [FilterList] {
        isLoading = true
        progress = 0
        
        // Ensure counts and versions are fresh before auto-update logic
        await updateVersionsAndCounts()

        let updatedFilters = await filterUpdater.autoUpdateFilters(
            filterLists: filterLists.filter { $0.isSelected },
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )
        
        saveFilterListsSync() // Save lists as autoUpdateFilters calls fetchAndProcessFilter

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

        let updatedSuccessfullyFilters = await filterUpdater.updateSelectedFilters(
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
        
        saveFilterListsSync()

        await applyChanges()
        isLoading = false
        progress = 0
    }

    func downloadSelectedFilters(_ selectedFilters: [FilterList]) async {
        isLoading = true
        progress = 0
        statusDescription = "Downloading filter updates..."

        let successfullyUpdatedFilters = await filterUpdater.updateSelectedFilters(
            selectedFilters,
            progressCallback: { newProgress in
                Task { @MainActor in
                    self.progress = newProgress
                }
            }
        )

        saveFilterListsSync()

        await MainActor.run {
            for filter in successfullyUpdatedFilters {
                self.availableUpdates.removeAll { $0.id == filter.id }
            }
        }

        isLoading = false
        progress = 0

        // Close the update popup and show apply progress sheet
        await MainActor.run {
            showingUpdatePopup = false
            showingApplyProgressSheet = true
        }

        // Automatically apply changes after download
        await applyChanges()
    }
    
    func downloadMissingItems() async {
        isLoading = true
        progress = 0
        statusDescription = "Downloading missing items..."

        let tempMissingFilters = self.missingFilters
        let tempMissingScripts = self.missingUserScripts
        let totalSteps = Float(tempMissingFilters.count + tempMissingScripts.count)
        var completedSteps: Float = 0
        var downloadedFiltersCount = 0
        var downloadedScriptsCount = 0

        // Download missing filters
        for filter in tempMissingFilters {
            let success = await filterUpdater.fetchAndProcessFilter(filter)
            if success {
                await MainActor.run {
                    self.missingFilters.removeAll { $0.id == filter.id }
                }
                downloadedFiltersCount += 1
            }
            completedSteps += 1
            await MainActor.run {
                self.progress = completedSteps / totalSteps
            }
        }

        // Download missing userscripts
        if let userScriptManager = filterUpdater.userScriptManager {
            for script in tempMissingScripts {
                if let url = script.url {
                    await userScriptManager.addUserScript(from: url)
                    await MainActor.run {
                        self.missingUserScripts.removeAll { $0.id == script.id }
                    }
                    downloadedScriptsCount += 1
                }
                completedSteps += 1
                await MainActor.run {
                    self.progress = completedSteps / totalSteps
                }
            }
        }

        saveFilterListsSync()

        isLoading = false
        progress = 0

        var message = "Downloaded "
        var parts: [String] = []
        if downloadedFiltersCount > 0 {
            parts.append("\(downloadedFiltersCount) filter\(downloadedFiltersCount == 1 ? "" : "s")")
        }
        if downloadedScriptsCount > 0 {
            parts.append("\(downloadedScriptsCount) userscript\(downloadedScriptsCount == 1 ? "" : "s")")
        }
        message += parts.joined(separator: " and ")
        message += ". Would you like to apply them now?"

        await MainActor.run {
            showMissingItemsSheet = false
            showingApplyProgressSheet = true
        }

        // Automatically apply changes after download
        await applyChanges()
    }
    

    // MARK: - List Management
    func addFilterList(name: String, urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusDescription = "Invalid URL provided: \(urlString)"
            hasError = true
            Task { await ConcurrentLogManager.shared.error(.system, "Invalid URL provided for new filter list", metadata: ["url": urlString]) }
            return
        }
        
        if filterLists.contains(where: { $0.url == url }) {
            statusDescription = "Filter list with this URL already exists: \(url.absoluteString)"
            hasError = true
            Task { await ConcurrentLogManager.shared.error(.system, "Filter list with URL already exists", metadata: ["url": url.absoluteString]) }
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
        Task { await ConcurrentLogManager.shared.info(.system, "Removed filters", metadata: ["filters": removedNames]) }
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
                await ConcurrentLogManager.shared.info(.system, "Added custom filter", metadata: ["filter": newFilterToAdd.name])
            }

            Task {
                let success = await filterUpdater.fetchAndProcessFilter(newFilterToAdd)
                if success {
                    await ConcurrentLogManager.shared.info(.filterUpdate, "Successfully downloaded custom filter", metadata: ["filter": newFilterToAdd.name])
                    await MainActor.run {
                        self.hasUnappliedChanges = true
                        self.statusDescription = "✅ Filter '\(newFilterToAdd.name)' added successfully. Apply changes to enable it."
                        self.hasError = false
                    }
                    saveFilterListsSync()
                } else {
                    await ConcurrentLogManager.shared.error(.filterUpdate, "Failed to download custom filter", metadata: ["filter": newFilterToAdd.name])
                    await MainActor.run {
                        removeCustomFilterList(newFilterToAdd)
                        self.statusDescription = "❌ Failed to add filter. The URL may be invalid or the content is not a valid filter list."
                        self.hasError = true
                    }
                }
            }
        } else {
            Task {
                await ConcurrentLogManager.shared.warning(.system, "Custom filter with URL already exists", metadata: ["url": filter.url.absoluteString])
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
            await ConcurrentLogManager.shared.info(.system, "Removed custom filter", metadata: ["filter": filter.name])
        }
        hasUnappliedChanges = true
    }

    func revertToRecommendedFilters() async {
        for index in filterLists.indices {
            filterLists[index].isSelected = false
        }


        #if os(iOS)
        let essentialFilters = [
            "AdGuard Base Filter",
            "EasyPrivacy"
        ]
        #else
        let essentialFilters = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "EasyPrivacy",
            "Online Security Filter"
        ]
        #endif

        for index in filterLists.indices {
            filterLists[index].isSelected = essentialFilters.contains(filterLists[index].name)
        }

        saveFilterListsSync()
        hasUnappliedChanges = false
        statusDescription = "Reverted to essential filters to stay under Safari's 150k rule limit."
        
        await MainActor.run {
            showingApplyProgressSheet = true
        }
        await applyChanges()
    }
    
    // Set the UserScriptManager for the filter updater
    public func setUserScriptManager(_ userScriptManager: UserScriptManager) {
        filterUpdater.userScriptManager = userScriptManager
    }
    
    /// Memory-efficient conversion that combines filter files using streaming I/O
    private func convertFiltersMemoryEfficient(filters: [FilterList], targetInfo: ContentBlockerTargetInfo, disabledSites: [String]) -> (safariRulesCount: Int, advancedRulesText: String?) {
        guard let containerURL = loader.getSharedContainerURL() else {
            return (safariRulesCount: 0, advancedRulesText: nil)
        }
        
        // Create a temporary combined file to avoid keeping large strings in memory
        let tempURL = containerURL.appendingPathComponent("temp_\(targetInfo.bundleIdentifier).txt")
        
        defer {
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        do {
            // Create temporary file handle for streaming write
            FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
            let fileHandle = try FileHandle(forWritingTo: tempURL)
            defer { try? fileHandle.close() }
            
            var totalSourceLines = 0
            
            // Stream each filter file directly to temp file
            for filter in filters {
                let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let data = try? Data(contentsOf: fileURL) {
                        try fileHandle.write(contentsOf: data)
                        try fileHandle.write(contentsOf: Data("\n".utf8))
                        
                        // Count lines efficiently without loading into memory
                        totalSourceLines += countLinesInData(data)
                    }
                }
            }
            
            try fileHandle.synchronize()
            
            // Log only for large conversions
            if totalSourceLines > 10000 {
                Task {
                    await ConcurrentLogManager.shared.debug(.filterApply, "Converting large category", metadata: ["category": targetInfo.primaryCategory.rawValue, "sourceLines": "\(totalSourceLines)"])
                }
            }
            
            // Read combined rules for conversion
            let combinedRules = try String(contentsOf: tempURL, encoding: .utf8)
            
            return ContentBlockerService.convertFilter(
                rules: combinedRules.isEmpty ? "" : combinedRules,
                groupIdentifier: GroupIdentifier.shared.value,
                targetRulesFilename: targetInfo.rulesFilename,
                disabledSites: disabledSites
            )
            
        } catch {
            Task {
                await ConcurrentLogManager.shared.error(.filterApply, "Error in memory-efficient conversion", metadata: ["error": "\(error)"])
            }
            return (safariRulesCount: 0, advancedRulesText: nil)
        }
    }
    
    /// Efficiently count lines in data without loading into String
    private func countLinesInData(_ data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        var count = 0
        let newline = UInt8(ascii: "\n")
        
        data.forEach { byte in
            if byte == newline {
                count += 1
            }
        }
        
        // Account for the last line if the file doesn't end with a newline
        if data.last != newline {
            count += 1
        }
        
        return count
    }
}
