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

let APP_CONTENT_BLOCKER_ID = "skula.wBlock.wBlock-Filters"

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
    @Published var whitelistViewModel = WhitelistViewModel()
    @Published var availableUpdates: [FilterList] = []
    @Published var showingUpdatePopup = false
    @Published var showingNoUpdatesAlert = false
    @Published var hasUnappliedChanges = false
    @Published var showMissingFiltersSheet = false
    @Published var showingApplyProgressSheet = false
    @Published var showingDownloadCompleteAlert = false
    @Published var downloadCompleteMessage = ""
    
    // iOS-specific extension handling
    @Published var showingExtensionSetupAlert = false
    @Published var extensionSetupMessage = ""
    @Published var disabledExtensionsList: [String] = []
    
    // Per-category rule count tracking
    @Published var ruleCountsByCategory: [FilterListCategory: Int] = [:]
    @Published var categoriesApproachingLimit: Set<FilterListCategory> = []
    @Published var showingCategoryWarningAlert = false
    @Published var categoryWarningMessage = ""
    
    // Performance tracking
    @Published var lastFastUpdateTime: String = "N/A"
    @Published var fastUpdateCount: Int = 0
    
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

    private func setupAsync() async {
        // Wait for ProtobufDataManager to finish loading
        while dataManager.isLoading {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        await MainActor.run {
            setup()
        }
        
        #if os(iOS)
        // Check extension status on iOS to help users diagnose issues
        await checkExtensionStatus()
        #endif
    }

    private func setup() {
        filterUpdater.filterListManager = self
        
        // Load filter lists from protobuf data manager
        filterLists = dataManager.getFilterLists()
        customFilterLists = dataManager.getCustomFilterLists()
        
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
        disabledSitesCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForDisabledSitesChanges()
            }
        }
    }
    
    /// Checks for changes in disabled sites and triggers fast rebuild if needed
    @MainActor
    private func checkForDisabledSitesChanges() async {
    let currentDisabledSites = dataManager.disabledSites
        
        if currentDisabledSites != lastKnownDisabledSites {
            await ConcurrentLogManager.shared.log("🔄 Disabled sites changed from \(lastKnownDisabledSites) to \(currentDisabledSites), fast rebuilding content blockers")
            
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
    
    /// Fast rebuild for disabled sites changes only - skips SafariConverterLib conversion
    private func fastApplyDisabledSitesChanges() async {
        await MainActor.run {
            self.isLoading = true
            self.statusDescription = "Updating disabled sites..."
        }
        
        await ConcurrentLogManager.shared.log("🚀 Fast applying disabled sites changes without full conversion")
        
        // Get all platform targets that need updating
        let currentPlatform = self.currentPlatform
        let platformTargets = await Task.detached {
            ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        }.value
        
        // Fast update each target's JSON files without full conversion
        await MainActor.run {
            self.conversionStageDescription = "Fast updating ignore rules..."
        }
        
        await Task.detached {
            for targetInfo in platformTargets {
                // Use fast update method that only modifies ignore rules
                _ = ContentBlockerService.fastUpdateDisabledSites(
                    groupIdentifier: GroupIdentifier.shared.value,
                    targetRulesFilename: targetInfo.rulesFilename
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
                    await ConcurrentLogManager.shared.log("⏩ Skipping reload for empty extension: \(targetInfo.primaryCategory.rawValue)")
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
        
        await ConcurrentLogManager.shared.log("✅ Fast disabled sites update completed: \(successCount)/\(platformTargets.count) extensions in \(reloadTime)")
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

        saveFilterListsSync()
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
    
    /// Checks if we can communicate with extensions (iOS-specific issue)
    func checkExtensionStatus() async {
        #if os(iOS)
        await ConcurrentLogManager.shared.log("📱 Checking iOS extension status...")
        
        let allTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        var enabledCount = 0
        var disabledExtensions: [String] = []
        
        for target in allTargets {
            // Try a quick reload to test if extension is enabled
            let result = ContentBlockerService.reloadContentBlocker(withIdentifier: target.bundleIdentifier)
            if case .success = result {
                enabledCount += 1
                await ConcurrentLogManager.shared.log("  ✅ \(target.primaryCategory.rawValue): Enabled")
            } else if case .failure(let error) = result {
                if error.localizedDescription.contains("Couldn't communicate with a helper application") {
                    disabledExtensions.append(target.primaryCategory.rawValue)
                    await ConcurrentLogManager.shared.log("  ❌ \(target.primaryCategory.rawValue): Not enabled in Settings")
                } else {
                    await ConcurrentLogManager.shared.log("  ⚠️ \(target.primaryCategory.rawValue): \(error.localizedDescription)")
                }
            }
        }
        
        if !disabledExtensions.isEmpty {
            await ConcurrentLogManager.shared.log("\n⚠️ IMPORTANT: The following extensions are not enabled:")
            for ext in disabledExtensions {
                await ConcurrentLogManager.shared.log("  - \(ext)")
            }
            await ConcurrentLogManager.shared.log("\n📲 To enable extensions on iOS:")
            await ConcurrentLogManager.shared.log("1. Open Settings app")
            await ConcurrentLogManager.shared.log("2. Go to Safari → Extensions")
            await ConcurrentLogManager.shared.log("3. Enable each wBlock extension")
            await ConcurrentLogManager.shared.log("4. Return to this app and try again\n")
            
            // Show UI alert for user
            await MainActor.run {
                self.disabledExtensionsList = disabledExtensions
                self.extensionSetupMessage = """
                The following Safari extensions need to be enabled manually in Settings:

                \(disabledExtensions.map { "• \($0)" }.joined(separator: "\n"))

                To enable them:
                1. Open Settings app
                2. Go to Safari → Extensions
                3. Toggle ON each wBlock extension
                4. Return to this app and try reloading
                """
                self.showingExtensionSetupAlert = true
            }
        } else if enabledCount == allTargets.count {
            await ConcurrentLogManager.shared.log("✅ All extensions are enabled and working!")
        }
        #else
        await ConcurrentLogManager.shared.log("🖥 macOS: Extension checks not needed")
        #endif
    }
    
    /// Opens iOS Settings app to the Safari Extensions section
    func openSafariExtensionSettings() {
        #if os(iOS)
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
        #endif
    }
    
    /// Attempts to reload a content blocker with up to 5 retry attempts
    /// Returns true if successful, false if all attempts failed
    private func reloadContentBlockerWithRetry(targetInfo: ContentBlockerTargetInfo) async -> Bool {
        let maxRetries = 5
        let categoryName = targetInfo.primaryCategory.rawValue
        
        // Debug logging
        await ConcurrentLogManager.shared.log("🔍 DEBUG: Attempting to reload extension:")
        await ConcurrentLogManager.shared.log("  - Category: \(categoryName)")
        await ConcurrentLogManager.shared.log("  - Bundle ID: \(targetInfo.bundleIdentifier)")
        await ConcurrentLogManager.shared.log("  - Platform: \(targetInfo.platform)")
        await ConcurrentLogManager.shared.log("  - Rules file: \(targetInfo.rulesFilename)")
        
        #if os(iOS)
        // iOS-specific checks
        await ConcurrentLogManager.shared.log("🔍 iOS Extension Debug:")
        await ConcurrentLogManager.shared.log("  - App Group ID: \(GroupIdentifier.shared.value)")
        
        // Check if we can create SFContentBlockerManager at all
        await ConcurrentLogManager.shared.log("  - Testing SFContentBlockerManager availability...")
        
        // Try to get state of content blocker
        await withCheckedContinuation { continuation in
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: targetInfo.bundleIdentifier) { state, error in
                Task {
                    if let error = error {
                        await ConcurrentLogManager.shared.log("  - Extension state check failed: \(error.localizedDescription)")
                        let nsError = error as NSError
                        await ConcurrentLogManager.shared.log("  - State error domain: \(nsError.domain), code: \(nsError.code)")
                    } else if let state = state {
                        await ConcurrentLogManager.shared.log("  - Extension state: enabled=\(state.isEnabled)")
                    } else {
                        await ConcurrentLogManager.shared.log("  - Extension state: no state returned")
                    }
                    continuation.resume()
                }
            }
        }
        #endif
        
        // Check if the rules file exists in app group
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) {
            let rulesFileURL = groupURL.appendingPathComponent(targetInfo.rulesFilename)
            let fileExists = FileManager.default.fileExists(atPath: rulesFileURL.path)
            await ConcurrentLogManager.shared.log("  - App Group URL: \(groupURL.path)")
            await ConcurrentLogManager.shared.log("  - Rules file exists: \(fileExists)")
            if fileExists {
                if let attributes = try? FileManager.default.attributesOfItem(atPath: rulesFileURL.path),
                   let fileSize = attributes[.size] as? Int64 {
                    await ConcurrentLogManager.shared.log("  - Rules file size: \(fileSize) bytes")
                    
                    // Check if file is too large (Safari has ~150k rule limit)
                    if fileSize > 1_000_000 { // 1MB threshold
                        await ConcurrentLogManager.shared.log("  ⚠️ Rules file is very large - may cause extension issues")
                    }
                    
                    // Try to validate JSON structure
                    do {
                        let jsonData = try Data(contentsOf: rulesFileURL)
                        let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
                        if let rulesArray = jsonObject as? [[String: Any]] {
                            await ConcurrentLogManager.shared.log("  - Rules count: \(rulesArray.count)")
                            if rulesArray.count > 150_000 {
                                await ConcurrentLogManager.shared.log("  ⚠️ Rules count exceeds Safari limit (150k)")
                            }
                        }
                    } catch {
                        await ConcurrentLogManager.shared.log("  ❌ Rules file JSON validation failed: \(error)")
                    }
                }
            }
            
            // Check app group permissions
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: groupURL.path)
                await ConcurrentLogManager.shared.log("  - App Group contents: \(contents.count) items")
            } catch {
                await ConcurrentLogManager.shared.log("  ❌ Cannot read app group directory: \(error)")
            }
        } else {
            await ConcurrentLogManager.shared.log("  ❌ Cannot access app group container!")
        }
        
        for attempt in 1...maxRetries {
            let result = ContentBlockerService.reloadContentBlocker(withIdentifier: targetInfo.bundleIdentifier)
            if case .success = result {
                if attempt > 1 {
                    await ConcurrentLogManager.shared.log("✅ \(categoryName) reloaded successfully (attempt \(attempt))")
                }
                return true
            } else if case .failure(let error) = result {
                let nsError = error as NSError
                await ConcurrentLogManager.shared.log("❌ \(categoryName) reload failed (attempt \(attempt)/\(maxRetries)):")
                await ConcurrentLogManager.shared.log("  - Error domain: \(nsError.domain)")
                await ConcurrentLogManager.shared.log("  - Error code: \(nsError.code)")
                await ConcurrentLogManager.shared.log("  - Error: \(error.localizedDescription)")
                
                // Check for specific error codes
                if nsError.domain == "WKErrorDomain" {
                    await ConcurrentLogManager.shared.log("  - WebKit error detected")
                    if nsError.code == 6 {
                        await ConcurrentLogManager.shared.log("  - Error code 6: Cannot access blocker list file")
                    }
                } else if nsError.domain == "NSCocoaErrorDomain" {
                    if nsError.code == 4097 {
                        await ConcurrentLogManager.shared.log("  - NSCocoaErrorDomain 4097: XPC Connection Interrupted")
                        await ConcurrentLogManager.shared.log("  - Possible causes: Extension crashed, memory pressure, or process termination")
                    } else if nsError.code == 4099 {
                        await ConcurrentLogManager.shared.log("  - NSCocoaErrorDomain 4099: XPC Connection Invalid")
                        await ConcurrentLogManager.shared.log("  - Possible causes: Extension not properly registered, permission issues, or service unavailable")
                        #if os(iOS)
                        await ConcurrentLogManager.shared.log("  - Even if enabled in Settings, extension may have issues loading")
                        #endif
                    } else {
                        await ConcurrentLogManager.shared.log("  - NSCocoaErrorDomain \(nsError.code): Unknown error")
                    }
                }
                
                #if os(iOS)
                // iOS-specific: Check if this might be an extension activation issue
                if error.localizedDescription.contains("Couldn't communicate with a helper application") {
                    await ConcurrentLogManager.shared.log("  ⚠️ iOS Extension not enabled in Settings > Safari > Extensions")
                    await ConcurrentLogManager.shared.log("  ⚠️ User must manually enable '\(categoryName)' extension")
                    
                    // On the final attempt, trigger the setup alert if not already shown
                    if attempt == maxRetries {
                        await MainActor.run {
                            if !self.showingExtensionSetupAlert {
                                self.disabledExtensionsList = [categoryName]
                                self.extensionSetupMessage = """
                                The '\(categoryName)' Safari extension is not enabled.
                                
                                Error: \(error.localizedDescription)
                                
                                To fix this:
                                1. Open Settings app
                                2. Go to Safari → Extensions
                                3. Toggle ON the '\(categoryName)' extension
                                4. Return to this app and try again
                                """
                                self.showingExtensionSetupAlert = true
                            }
                        }
                    }
                }
                #endif
                
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
            self.statusDescription = "Applying filters...\n(This may take a while)"
            
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
        
        // Give the UI a chance to update before starting heavy operations
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms delay
        
        await ConcurrentLogManager.shared.log("🚀 Starting filter application process on \(currentPlatform == .macOS ? "macOS" : "iOS")")

        let allSelectedFilters = await MainActor.run { self.filterLists.filter { $0.isSelected } }

        if allSelectedFilters.isEmpty {
            await MainActor.run {
                self.statusDescription = "No filter lists selected. Clearing rules from all extensions."
            }
            await ConcurrentLogManager.shared.log("🧹 No filters selected - clearing all extensions")
            
            // Perform heavy operations on background thread
            let currentPlatform = self.currentPlatform
            await Task.detached {
                // Clear the filter engine when no filters are selected
                ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)
                
                // Clear rules for all relevant extensions
                let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
                for targetInfo in platformTargets {
                    _ = ContentBlockerService.convertFilter(rules: "", groupIdentifier: GroupIdentifier.shared.value, targetRulesFilename: targetInfo.rulesFilename).safariRulesCount
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
        
        // Group filters by their target ContentBlockerTargetInfo
        var rulesByTargetInfo: [ContentBlockerTargetInfo: String] = [:]
        var sourceRulesByTargetInfo: [ContentBlockerTargetInfo: Int] = [:]

        for filter in allSelectedFilters {
            guard let targetInfo = ContentBlockerTargetManager.shared.targetInfo(forCategory: filter.category, platform: self.currentPlatform) else {
                await ConcurrentLogManager.shared.log("Warning: No target extension found for category \(filter.category.rawValue) on \(self.currentPlatform == .macOS ? "macOS" : "iOS"). Skipping filter: \(filter.name)")
                continue
            }

            let containerURL = await MainActor.run { self.loader.getSharedContainerURL() }
            guard let containerURL = containerURL else {
                await MainActor.run {
                    self.statusDescription = "Error: Unable to access shared container for \(filter.name)"
                    self.hasError = true
                    self.isLoading = false
                    self.showingApplyProgressSheet = false
                }
                return
            }
            
            // Run file I/O on background thread
            let contentToAppend = await Task.detached {
                let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")
                var content = ""
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    do {
                        content = try String(contentsOf: fileURL, encoding: .utf8) + "\n"
                    } catch {
                        await ConcurrentLogManager.shared.log("Error reading \(filter.name): \(error)")
                    }
                } else {
                    await ConcurrentLogManager.shared.log("Warning: Filter file for \(filter.name) not found locally.")
                }
                return content
            }.value
            
            rulesByTargetInfo[targetInfo, default: ""] += contentToAppend
            sourceRulesByTargetInfo[targetInfo, default: 0] += filter.sourceRuleCount ?? contentToAppend.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.hasPrefix("!") && !$0.hasPrefix("[") }.count
        }
        
        let totalFiltersCount = rulesByTargetInfo.keys.count
        await MainActor.run {
            self.sourceRulesCount = sourceRulesByTargetInfo.values.reduce(0, +) // Sum of all source rules for UI
            self.totalFiltersCount = totalFiltersCount // Number of unique extensions to process
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
        }

        // Collect all advanced rules from all targets to build the engine once
        var allAdvancedRules: [String] = []
        var advancedRulesByTarget: [String: String] = [:] // Track advanced rules by target bundle ID
        for (targetInfo, rulesString) in rulesByTargetInfo {
            await MainActor.run {
                self.processedFiltersCount += 1
                self.progress = Float(self.processedFiltersCount) / Float(totalFiltersCount) * 0.7 // Up to 70% for conversion
                self.currentFilterName = targetInfo.primaryCategory.rawValue // More user-friendly
                self.conversionStageDescription = "Converting \(targetInfo.primaryCategory.rawValue)..."
                self.isInSavingPhase = true // Set saving phase for each conversion
            }
            
            // Log conversion start with source line count (only for large sets)
            let sourceLineCount = rulesString.components(separatedBy: .newlines).count
            if sourceLineCount > 10000 {
                await ConcurrentLogManager.shared.log("🔄 Converting \(targetInfo.primaryCategory.rawValue) (\(sourceLineCount) source lines - LARGE)")
            }
            
            try? await Task.sleep(nanoseconds: 50_000_000) // UI update chance

            // Perform heavy conversion on background thread
            let conversionResult = await Task.detached {
                return ContentBlockerService.convertFilter(
                    rules: rulesString.isEmpty ? "" : rulesString, // Use empty string instead of "[]"
                    groupIdentifier: GroupIdentifier.shared.value,
                    targetRulesFilename: targetInfo.rulesFilename
                )
            }.value
            
            await MainActor.run {
                self.isInSavingPhase = false // Clear saving phase after conversion
            }
            
            let ruleCountForThisTarget = conversionResult.safariRulesCount
            
            // Collect advanced rules for later engine building
            if let advancedRulesText = conversionResult.advancedRulesText, !advancedRulesText.isEmpty {
                allAdvancedRules.append(advancedRulesText)
                advancedRulesByTarget[targetInfo.bundleIdentifier] = advancedRulesText
            }
            
            // Single consolidated log per target
            let advancedCount = conversionResult.advancedRulesText?.isEmpty == false ? conversionResult.advancedRulesText!.components(separatedBy: .newlines).count : 0
            await ConcurrentLogManager.shared.log("✅ \(targetInfo.primaryCategory.rawValue): \(ruleCountForThisTarget) Safari rules, \(advancedCount) advanced rules")
            
            // Update per-category rule count on main thread
            await MainActor.run {
                self.ruleCountsByCategory[targetInfo.primaryCategory] = ruleCountForThisTarget
            }

            let ruleLimit = 150000
            let warningThreshold = Int(Double(ruleLimit) * 0.8) // 80% threshold
            
            // Check if this category is approaching the limit
            await MainActor.run {
                if ruleCountForThisTarget >= warningThreshold && ruleCountForThisTarget < ruleLimit {
                    self.categoriesApproachingLimit.insert(targetInfo.primaryCategory)
                } else {
                    self.categoriesApproachingLimit.remove(targetInfo.primaryCategory)
                }
            }
            
            if ruleCountForThisTarget > ruleLimit {
                await ConcurrentLogManager.shared.log("CRITICAL: Rule limit \(ruleLimit) exceeded for \(targetInfo.bundleIdentifier) with \(ruleCountForThisTarget) rules.")
                
                // Auto-reset this specific category and warn the user
                await resetCategoryToRecommended(targetInfo.primaryCategory)
                
                // Show category warning alert to inform user about the rule limit exceeded
                await MainActor.run {
                    self.showCategoryWarning(for: targetInfo.primaryCategory)
                    // self.statusDescription = "Auto-reset \(targetInfo.primaryCategory.rawValue) filters due to rule limit exceeded (\(ruleCountForThisTarget)/\(ruleLimit)). Continuing with other categories..."
                }
                await ConcurrentLogManager.shared.log("Auto-reset category \(targetInfo.primaryCategory.rawValue) due to rule limit exceeded.")
                
                // Re-process this target with the reset filters - on background thread
                let resetResult = await Task.detached {
                    let containerURL = await MainActor.run { self.loader.getSharedContainerURL() }
                    var resetRulesString = ""
                    
                    // FIX: Get the updated filter list after reset instead of using the old allSelectedFilters
                    let updatedSelectedFilters = await MainActor.run { self.filterLists.filter { $0.isSelected } }
                    
                    for filter in updatedSelectedFilters {
                        if filter.category == targetInfo.primaryCategory {
                            guard let containerURL = containerURL else { continue }
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
                    
                    return ContentBlockerService.convertFilter(
                        rules: resetRulesString.isEmpty ? "[]" : resetRulesString,
                        groupIdentifier: GroupIdentifier.shared.value,
                        targetRulesFilename: targetInfo.rulesFilename
                    )
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
                } else {
                    // Remove advanced rules for this target if reset resulted in none
                    if let existingAdvancedRules = advancedRulesByTarget[targetInfo.bundleIdentifier],
                       let existingIndex = allAdvancedRules.firstIndex(of: existingAdvancedRules) {
                        allAdvancedRules.remove(at: existingIndex)
                        advancedRulesByTarget.removeValue(forKey: targetInfo.bundleIdentifier)
                    }
                }
                
                await MainActor.run {
                    self.ruleCountsByCategory[targetInfo.primaryCategory] = resetRuleCount
                    self.categoriesApproachingLimit.remove(targetInfo.primaryCategory)
                }
                
                overallSafariRulesApplied += resetRuleCount
                await ConcurrentLogManager.shared.log("🔄 After reset, \(targetInfo.primaryCategory.rawValue) now has \(resetRuleCount) rules")
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
        }
        await ConcurrentLogManager.shared.log("✅ All conversions finished: \(overallSafariRulesApplied) Safari rules in \(await MainActor.run { self.lastConversionTime })")

        // Reloading phase - reload all content blockers FIRST before building advanced engine
        await MainActor.run {
            self.conversionStageDescription = "Reloading Safari extensions..."
            self.isInReloadPhase = true
            self.processedFiltersCount = 0
        }
        
        let overallReloadStartTime = Date()
        var allReloadsSuccessful = true
        
        for targetInfo in rulesByTargetInfo.keys { // Reload only affected targets
            await MainActor.run {
                self.processedFiltersCount += 1
                self.progress = 0.7 + (Float(self.processedFiltersCount) / Float(totalFiltersCount) * 0.2) // 70% to 90%
                self.currentFilterName = targetInfo.primaryCategory.rawValue
            }
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
        let allPlatformTargets = await Task.detached {
            ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        }.value
        let affectedTargetBundleIDs = Set(rulesByTargetInfo.keys.map { $0.bundleIdentifier })
        
        for targetInfo in allPlatformTargets {
            if !affectedTargetBundleIDs.contains(targetInfo.bundleIdentifier) {
                 // Run conversion and reload on background thread
                 await Task.detached {
                     _ = ContentBlockerService.convertFilter(rules: "", groupIdentifier: GroupIdentifier.shared.value, targetRulesFilename: targetInfo.rulesFilename).safariRulesCount // Ensure it has an empty list
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
            await ConcurrentLogManager.shared.log("✅ All content blocker reloads completed successfully in \(await MainActor.run { self.lastReloadTime })")
        } else {
            await ConcurrentLogManager.shared.log("⚠️ Some content blocker reloads failed after retries, continuing with advanced rules processing")
        }

        // Small delay before building advanced engine to let system recover from reloads
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
        
        // NOW build the combined filter engine AFTER all content blockers are reloaded
        await MainActor.run {
            self.progress = 0.9
        }
        
        if !allAdvancedRules.isEmpty {
            await MainActor.run {
                self.conversionStageDescription = "Building combined filter engine..."
                self.isInEnginePhase = true
            }
            
            // Run engine building on background thread
            await Task.detached {
                let combinedAdvancedRules = allAdvancedRules.joined(separator: "\n")
                let totalLines = combinedAdvancedRules.components(separatedBy: "\n").count
                await ConcurrentLogManager.shared.log("🔧 Building filter engine with \(allAdvancedRules.count) groups (\(totalLines) lines)")
                
                ContentBlockerService.buildCombinedFilterEngine(
                    combinedAdvancedRules: combinedAdvancedRules,
                    groupIdentifier: GroupIdentifier.shared.value
                )
            }.value
            
            await MainActor.run {
                self.isInEnginePhase = false
            }
        } else {
            await ConcurrentLogManager.shared.log("🔧 No advanced rules found, clearing filter engine")
            // Run on background thread
            await Task.detached {
                ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)
            }.value
        }
        
        await MainActor.run {
            self.progress = 1.0
        }

        let hasErrorValue = await MainActor.run { self.hasError }
        if allReloadsSuccessful && !hasErrorValue {
            await MainActor.run {
                self.conversionStageDescription = "Process completed successfully!"
                self.statusDescription = "Applied rules to \(rulesByTargetInfo.keys.count) blocker(s). Total: \(overallSafariRulesApplied) Safari rules. Advanced engine: \(allAdvancedRules.isEmpty ? "cleared" : "\(allAdvancedRules.count) groups combined")."
                self.hasUnappliedChanges = false
            }
        } else if !hasErrorValue { // Implies reload issue was the only problem
            await MainActor.run {
                self.conversionStageDescription = "Conversion completed with reload issues"
                self.statusDescription = "Converted rules, but one or more extensions failed to reload after 5 attempts. Advanced engine: \(allAdvancedRules.isEmpty ? "cleared" : "\(allAdvancedRules.count) groups combined")."
            }
        } // If hasError was already true, statusDescription would reflect the earlier error.

        await MainActor.run {
            self.isLoading = false
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
            await ConcurrentLogManager.shared.log("🎉 Process completed successfully: \(statusDesc)")
        } else if !hasErrorValueForLog {
            await ConcurrentLogManager.shared.log("⚠️ Process completed with reload issues: \(statusDesc)")
        } else {
            await ConcurrentLogManager.shared.log("❌ Process completed with errors: \(statusDesc)")
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
            let success = await filterUpdater.fetchAndProcessFilter(filter)
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
        
        saveFilterListsSync()

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
                let success = await filterUpdater.fetchAndProcessFilter(newFilterToAdd)
                if success {
                    await ConcurrentLogManager.shared.log("Successfully downloaded custom filter: \(newFilterToAdd.name)")
                    hasUnappliedChanges = true
                    saveFilterListsSync()
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
}

