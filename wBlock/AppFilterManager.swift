//
//  AppFilterManager.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import Combine
import CryptoKit
import SwiftUI
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
    private var missingFilters: [FilterList] = []
    private var missingUserScripts: [UserScript] = []
    @Published var whitelistViewModel = WhitelistViewModel()
    @Published var availableUpdates: [FilterList] = []
    @Published var showingUpdatePopup = false
    @Published var showingNoUpdatesAlert = false
    @Published var hasUnappliedChanges = false
    @Published var showingApplyProgressSheet = false
    @Published var suppressBlockingOverlay = false
    @Published var autoDisabledFilters: [FilterList] = []  // Filters auto-disabled due to rule limits
    @Published var showingAutoDisabledAlert = false

    // Per-extension rule count tracking (extension bundle ID -> Safari rule count)
    // This is the source of truth since extensions can serve multiple categories
    @Published var ruleCountsByExtension: [String: Int] = [:]
    @Published var extensionsApproachingLimit: Set<String> = []
    @Published var showingRuleLimitWarningAlert = false
    @Published var ruleLimitWarningMessage = ""

    // Performance tracking
    @Published var lastFastUpdateTime: String = "N/A"
    @Published var fastUpdateCount: Int = 0

    // New ViewModel-based progress tracking
    @Published var applyProgressViewModel = ApplyChangesViewModel()

    // Internal counters used for apply-run summary/progress math.
    private var sourceRulesCount: Int = 0
    private var processedFiltersCount: Int = 0
    @Published var currentPlatform: Platform

    // Dependencies
    private let loader: FilterListLoader
    private(set) var filterUpdater: FilterListUpdater
    private let logManager: ConcurrentLogManager
    private let dataManager = ProtobufDataManager.shared

    // Per-site disable tracking
    private var lastKnownDisabledSites: [String] = []
    private var disabledSitesDirectoryMonitor: DispatchSourceFileSystemObject?
    private var disabledSitesDirectoryFileDescriptor: CInt = -1
    private var pendingDisabledSitesCheckTask: Task<Void, Never>?
    private let disabledSitesMonitorQueue = DispatchQueue(
        label: "skula.wBlock.disabled-sites-monitor",
        qos: .utility
    )

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
        self.loader = FilterListLoader()
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
        ruleCountsByExtension = [:]
        extensionsApproachingLimit = []
        showingRuleLimitWarningAlert = false
        ruleLimitWarningMessage = ""
        lastRuleCount = 0
        lastFastUpdateTime = "N/A"
        fastUpdateCount = 0
        sourceRulesCount = 0
        processedFiltersCount = 0

        filterLists = []
        customFilterLists = []

        let defaultLists = loader.getDefaultFilterLists()
        filterLists = defaultLists
        saveFilterListsSync()

        await dataManager.updateRuleCounts(
            lastRuleCount: 0,
            ruleCountsByIdentifier: [:],
            identifiersApproachingLimit: []
        )

        ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)

        statusDescription = "Ready."
        isLoading = false
    }

    private func setupAsync() async {
        await dataManager.waitUntilLoaded()
        setup()
    }

    private func setup() {
        filterUpdater.filterListManager = self

        // Load filter lists from protobuf data manager
        var storedFilterLists = dataManager.getFilterLists()

        // Migrate old AdGuard Annoyances filter to new split filters
        storedFilterLists = migrateOldAnnoyancesFilter(in: storedFilterLists)

        // Enable AdGuard Extra for existing users who had it disabled
        enableAdGuardExtraForExistingUsersIfNeeded()

        // Remove deprecated filter lists that are no longer shipped by wBlock.
        let deprecatedFilterLists = storedFilterLists.filter { filter in
            !filter.isCustom
                && (filter.name == "AdGuard URL Tracking Filter"
                    || filter.url.absoluteString.contains("filter_17_TrackParam"))
        }
        if !deprecatedFilterLists.isEmpty {
            let removedSelected = deprecatedFilterLists.contains(where: { $0.isSelected })
            storedFilterLists.removeAll { filter in
                !filter.isCustom
                    && (filter.name == "AdGuard URL Tracking Filter"
                        || filter.url.absoluteString.contains("filter_17_TrackParam"))
            }

            let deprecatedFilterIDs = deprecatedFilterLists.map(\.id)
            Task {
                for id in deprecatedFilterIDs {
                    await self.dataManager.removeFilterList(withId: id)
                }
                await ConcurrentLogManager.shared.info(
                    .system, "Removed deprecated filter list(s)",
                    metadata: ["filters": deprecatedFilterLists.map(\.name).joined(separator: ", ")]
                )
            }

            if removedSelected {
                hasUnappliedChanges = true
            }
        }

        var migratedFilterLists = loader.migrateFilterURLs(in: storedFilterLists)
        customFilterLists = dataManager.getCustomFilterLists()

        // Merge any new default filters added in app updates
        if !migratedFilterLists.isEmpty {
            let defaultLists = loader.getDefaultFilterLists()
            let existingURLs = Set(migratedFilterLists.map { $0.url })

            for defaultFilter in defaultLists {
                if !existingURLs.contains(defaultFilter.url) {
                    // New filter from app update - add unselected
                    var newFilter = defaultFilter
                    newFilter.isSelected = false
                    migratedFilterLists.append(newFilter)
                }
            }
        }

        filterLists = migratedFilterLists

        // Ensure custom filter files use ID-based filenames so users can rename lists safely.
        Task.detached(priority: .utility) { [loader, migratedFilterLists] in
            for filter in migratedFilterLists where filter.isCustom {
                loader.migrateCustomFilterFileIfNeeded(filter)
            }
        }

        // Persist migrated filter URLs to the data store when needed
        if storedFilterLists != migratedFilterLists {
            Task {
                for migrated in migratedFilterLists {
                    if let original = storedFilterLists.first(where: { $0.id == migrated.id }),
                        original.url != migrated.url
                    {
                        await self.dataManager.updateFilterList(migrated)
                    }
                }
                // Also persist any newly added filters
                if migratedFilterLists.count > storedFilterLists.count {
                    await self.saveFilterLists()
                }
            }
        }

        // Only load defaults if truly no data exists
        if filterLists.isEmpty && !dataManager.isLoading {
            let defaultLists = loader.getDefaultFilterLists()
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
        // Store the last known disabled sites to detect changes.
        lastKnownDisabledSites = dataManager.disabledSites

        disabledSitesDirectoryMonitor?.cancel()
        disabledSitesDirectoryMonitor = nil
        pendingDisabledSitesCheckTask?.cancel()
        pendingDisabledSitesCheckTask = nil

        guard let directoryURL = dataManager.protobufDataDirectoryURL() else {
            Task {
                await ConcurrentLogManager.shared.warning(
                    .whitelist,
                    "Disabled sites monitor unavailable (no protobuf data directory)",
                    metadata: [:]
                )
            }
            return
        }

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Task {
                await ConcurrentLogManager.shared.warning(
                    .whitelist,
                    "Failed to start disabled sites monitor",
                    metadata: ["directory": directoryURL.path]
                )
            }
            return
        }

        disabledSitesDirectoryFileDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend],
            queue: disabledSitesMonitorQueue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.pendingDisabledSitesCheckTask?.cancel()
            self.pendingDisabledSitesCheckTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                await self.checkForDisabledSitesChanges()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.disabledSitesDirectoryFileDescriptor >= 0 {
                close(self.disabledSitesDirectoryFileDescriptor)
                self.disabledSitesDirectoryFileDescriptor = -1
            }
        }

        disabledSitesDirectoryMonitor = source
        source.resume()
    }

    /// Checks for changes in disabled sites and triggers fast rebuild if needed
    @MainActor
    private func checkForDisabledSitesChanges() async {
        // Only reload protobuf data when the shared file actually changed
        _ = await dataManager.refreshFromDiskIfModified()

        let currentDisabledSites = dataManager.disabledSites

        if currentDisabledSites != lastKnownDisabledSites {
            await ConcurrentLogManager.shared.info(
                .whitelist, "Disabled sites changed, fast rebuilding content blockers",
                metadata: [
                    "previousCount": "\(lastKnownDisabledSites.count)",
                    "newCount": "\(currentDisabledSites.count)",
                ])

            lastKnownDisabledSites = currentDisabledSites
            await MainActor.run { self.whitelistViewModel.loadWhitelistedDomains() }

            // Only rebuild if we have applied filters (don't rebuild on startup)
            if !hasUnappliedChanges && lastRuleCount > 0 {
                await fastApplyDisabledSitesChanges()
            }
        }
    }

    /// Clean up disabled-sites monitor resources when the object is deallocated.
    deinit {
        pendingDisabledSitesCheckTask?.cancel()
        disabledSitesDirectoryMonitor?.cancel()
        disabledSitesDirectoryMonitor = nil
        if disabledSitesDirectoryFileDescriptor >= 0 {
            close(disabledSitesDirectoryFileDescriptor)
            disabledSitesDirectoryFileDescriptor = -1
        }
    }

    // MARK: - Migration

    private func migrateOldAnnoyancesFilter(in filters: [FilterList]) -> [FilterList] {
        var result = filters
        var needsSave = false

        // Migration 1: Replace old combined AdGuard Annoyances Filter (14) with split filters (18-22)
        if let oldFilterIndex = result.firstIndex(where: {
            $0.url.absoluteString.contains("14_optimized.txt")
        }) {
            let wasSelected = result[oldFilterIndex].isSelected
            result.remove(at: oldFilterIndex)
            needsSave = true

            let newFilters: [(name: String, url: String, description: String)] = [
                (
                    "AdGuard Cookie Notices",
                    "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/18_optimized.txt",
                    "Blocks cookie consent notices on web pages."
                ),
                (
                    "AdGuard Popups",
                    "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/19_optimized.txt",
                    "Blocks promotional pop-ups, newsletter sign-ups, and notification requests."
                ),
                (
                    "AdGuard Mobile App Banners",
                    "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/20_optimized.txt",
                    "Blocks banners promoting mobile app downloads."
                ),
                (
                    "AdGuard Other Annoyances",
                    "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/21_optimized.txt",
                    "Blocks miscellaneous irritating elements not covered by other filters."
                ),
                (
                    "AdGuard Widgets",
                    "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/22_optimized.txt",
                    "Blocks third-party widgets, chat assistants, and support widgets."
                ),
            ]

            for filter in newFilters
            where !result.contains(where: { $0.url.absoluteString.contains(filter.url) }) {
                result.append(
                    FilterList(
                        id: UUID(),
                        name: filter.name,
                        url: URL(string: filter.url)!,
                        category: .annoyances,
                        isSelected: wasSelected,
                        description: filter.description
                    ))
            }
        }

        // Migration 2: Remove duplicate iOS-specific "AdGuard Mobile App Banners" filter
        let hasMainMobileAppBanners = result.contains(where: {
            $0.url.absoluteString.contains("FiltersRegistry")
                && $0.url.absoluteString.contains("20_optimized.txt")
        })
        if hasMainMobileAppBanners {
            let countBefore = result.count
            result.removeAll(where: {
                $0.url.absoluteString.contains("filters.adtidy.org/ios/filters/20_optimized.txt")
            })
            if result.count != countBefore {
                needsSave = true
            }
        }

        if needsSave {
            Task { await dataManager.updateFilterLists(result) }
        }
        return result
    }

    private func enableAdGuardExtraForExistingUsersIfNeeded() {
        let migrationKey = "adguardExtraEnabledByDefaultMigration_v1"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        UserDefaults.standard.set(true, forKey: migrationKey)

        Task {
            let manager = await UserScriptManager.shared
            await manager.waitUntilReady()
            let adguardExtraURL = "https://userscripts.adtidy.org/release/adguard-extra/1.0/adguard-extra.user.js"
            let scripts = await manager.userScripts
            guard let script = scripts.first(where: { $0.url?.absoluteString == adguardExtraURL }),
                  !script.isEnabled else { return }
            await manager.setUserScript(script, isEnabled: true)
        }
    }

    /// Fast rebuild for disabled sites changes only - skips SafariConverterLib conversion
    private func fastApplyDisabledSitesChanges() async {
        await MainActor.run {
            self.isLoading = true
            self.statusDescription = "Updating disabled sites..."
        }

        await ConcurrentLogManager.shared.info(
            .whitelist, "Fast applying disabled sites changes without full conversion",
            metadata: [:])

        // Get all platform targets that need updating
        let currentPlatform = self.currentPlatform
        let platformTargets = await Task.detached {
            ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        }.value

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

        let overallReloadStartTime = Date()
        var successCount = 0

        for targetInfo in platformTargets {
            // Check if this extension has any rules before reloading
            let rulesCount = self.ruleCountsByExtension[targetInfo.bundleIdentifier] ?? 0
            if rulesCount > 0 {
                let reloadSuccess = await reloadContentBlockerWithRetry(targetInfo: targetInfo)
                if reloadSuccess {
                    successCount += 1
                }
                // Small delay between reloads to reduce memory pressure
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            } else {
                // Skip reload for empty extensions
                await ConcurrentLogManager.shared.debug(
                    .filterApply, "Skipping reload for empty extension",
                    metadata: ["blocker": targetInfo.displayName])
            }
        }

        let reloadTime = String(format: "%.2fs", Date().timeIntervalSince(overallReloadStartTime))

        await MainActor.run {
            self.lastReloadTime = reloadTime
            self.lastFastUpdateTime = reloadTime
            self.fastUpdateCount += 1
            self.isLoading = false

            if successCount == platformTargets.count {
                self.statusDescription =
                    "✅ Disabled sites updated successfully in \(reloadTime) (fast update #\(self.fastUpdateCount))"
            } else {
                self.statusDescription =
                    "⚠️ Updated \(successCount)/\(platformTargets.count) extensions in \(reloadTime)"
            }
        }

        await ConcurrentLogManager.shared.info(
            .whitelist, "Fast disabled sites update completed",
            metadata: [
                "successCount": "\(successCount)", "totalCount": "\(platformTargets.count)",
                "reloadTime": reloadTime,
            ])
    }

    private func loadSavedRuleCounts() {
        // Load last known rule count from protobuf data
        lastRuleCount = dataManager.lastRuleCount

        // Load extension-specific rule counts
        // Stored keys may be legacy category names or (new) bundle identifiers.
        for (categoryKey, count) in dataManager.ruleCountsByCategory {
            if ContentBlockerTargetManager.shared.targetInfo(forBundleIdentifier: categoryKey, platform: currentPlatform) != nil {
                ruleCountsByExtension[categoryKey] = Int(count)
                continue
            }

            if let category = FilterListCategory(rawValue: categoryKey),
               let legacyBundleID = legacyBundleIdentifier(for: category) {
                if ruleCountsByExtension[legacyBundleID] == nil {
                    ruleCountsByExtension[legacyBundleID] = Int(count)
                }
            }
        }

        // Load extensions approaching limit (legacy category names or bundle identifiers).
        for identifierOrCategory in dataManager.categoriesApproachingLimit {
            if ContentBlockerTargetManager.shared.targetInfo(forBundleIdentifier: identifierOrCategory, platform: currentPlatform) != nil {
                extensionsApproachingLimit.insert(identifierOrCategory)
                continue
            }
            if let category = FilterListCategory(rawValue: identifierOrCategory),
               let legacyBundleID = legacyBundleIdentifier(for: category) {
                extensionsApproachingLimit.insert(legacyBundleID)
            }
        }
    }

    private func saveRuleCounts() {
        Task { @MainActor in
            let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
            let countsByIdentifier = Dictionary(
                uniqueKeysWithValues: platformTargets.map { target in
                    (target.bundleIdentifier, ruleCountsByExtension[target.bundleIdentifier] ?? 0)
                }
            )
            let approaching = Set(platformTargets.map(\.bundleIdentifier)).intersection(extensionsApproachingLimit)

            await dataManager.updateRuleCounts(
                lastRuleCount: lastRuleCount,
                ruleCountsByIdentifier: countsByIdentifier,
                identifiersApproachingLimit: approaching
            )
        }
    }

    private func legacyBundleIdentifier(for category: FilterListCategory) -> String? {
        let slot: Int?
        switch category {
        case .ads:
            slot = 1
        case .privacy:
            slot = 2
        case .security, .annoyances, .multipurpose:
            slot = 3
        case .foreign, .experimental:
            slot = 4
        case .custom:
            slot = 5
        default:
            slot = nil
        }

        guard let slot = slot else { return nil }
        return ContentBlockerTargetManager.shared
            .allTargets(forPlatform: currentPlatform)
            .first { $0.slot == slot }?
            .bundleIdentifier
    }

    func updateVersionsAndCounts() async {
        let initiallyLoadedLists = self.filterLists
        let updater = self.filterUpdater
        let updatedListsFromServer = await Task.detached(priority: .utility) {
            await updater.updateMissingVersionsAndCounts(filterLists: initiallyLoadedLists)
        }.value

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
        let updater = self.filterUpdater
        let updatedFilters = await Task.detached(priority: .utility) {
            await updater.updateMissingVersionsAndCounts(filterLists: [filter])
        }.value

        guard let updatedFilter = updatedFilters.first,
            let index = self.filterLists.firstIndex(where: { $0.id == filter.id })
        else {
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

        for filter in filterLists where filter.isSelected && !loader.filterFileExists(filter) {
            missingFilters.append(filter)
        }

        if let userScriptManager = filterUpdater.userScriptManager {
            for script in userScriptManager.userScripts
            where script.isEnabled && !script.isDownloaded {
                missingUserScripts.append(script)
            }
        }

        if !missingFilters.isEmpty || !missingUserScripts.isEmpty || forceReload
            || hasUnappliedChanges
        {
            prepareApplyRunState()
            showingApplyProgressSheet = true
            Task {
                if !missingFilters.isEmpty || !missingUserScripts.isEmpty {
                    await downloadMissingItemsSilently()
                }
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
                "Anti-Adblock List",
            ]
        #else
            let recommendedFilters = [
                "AdGuard Base Filter",
                "AdGuard Tracking Protection Filter",
                "AdGuard Annoyances Filter",
                "EasyPrivacy",
                "Online Security Filter",
                "d3Host List by d3ward",
                "Anti-Adblock List",
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

    // MARK: - Rule limit UX

    func showRuleLimitWarning(for filter: FilterList? = nil) {
        let ruleLimitPerBlocker = 150_000
        let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        let totalCapacity = platformTargets.count * ruleLimitPerBlocker

        let totalRules = lastRuleCount
        let totalWarningThreshold = Int(Double(totalCapacity) * 0.8)

        var message = ""
        if let filter, let reason = filter.limitExceededReason, !reason.isEmpty {
            message = reason
        } else {
            message = """
            Safari limits each content blocker extension to \(ruleLimitPerBlocker.formatted()) rules.
            Total capacity (all wBlock blockers): \(totalCapacity.formatted()) rules.

            Current Safari rules: \(totalRules.formatted())\(totalRules >= totalWarningThreshold ? " (near limit)" : "")

            wBlock distributes your enabled filter lists across multiple blockers to maximize capacity, but you may still hit Safari's limits if you enable too many large lists.
            """
        }

        let perBlockerWarningThreshold = Int(Double(ruleLimitPerBlocker) * 0.8)
        let nearLimitBlockers = platformTargets
            .map { target -> (name: String, count: Int) in
                (target.displayName, ruleCountsByExtension[target.bundleIdentifier] ?? 0)
            }
            .filter { $0.count >= perBlockerWarningThreshold }
            .sorted { $0.count > $1.count }

        if !nearLimitBlockers.isEmpty {
            message += "\n\nBlockers near the per-extension limit:\n" + nearLimitBlockers
                .map { "\($0.name): \($0.count.formatted())" }
                .joined(separator: "\n")
        }

        ruleLimitWarningMessage = message
        showingRuleLimitWarningAlert = true
    }

    // MARK: - Helper Methods

    /// Attempts to reload a content blocker with up to 5 retry attempts
    /// Returns true if successful, false if all attempts failed
    private func reloadContentBlockerWithRetry(targetInfo: ContentBlockerTargetInfo) async -> Bool {
        let blockerName = targetInfo.displayName
        let reloadResult = await Self.reloadWithRetry(
            identifier: targetInfo.bundleIdentifier,
            maxRetries: 5
        )

        if reloadResult.success {
            if reloadResult.attempts > 1 {
                await ConcurrentLogManager.shared.info(
                    .filterApply,
                    "Content blocker reloaded after retry",
                    metadata: [
                        "blocker": blockerName,
                        "attempts": "\(reloadResult.attempts)",
                        "durationMs": "\(reloadResult.durationMs)",
                    ]
                )
            }
            return true
        }

        await ConcurrentLogManager.shared.error(
            .filterApply,
            "Content blocker reload failed after retries",
            metadata: [
                "blocker": blockerName,
                "attempts": "\(reloadResult.attempts)",
                "maxRetries": "5",
                "durationMs": "\(reloadResult.durationMs)",
            ]
        )
        return false
    }

    // MARK: - Delegated methods

    func applyChanges(allowUserInteraction: Bool = false) async {
        suppressBlockingOverlay = allowUserInteraction
        defer { suppressBlockingOverlay = false }

        await MainActor.run { self.prepareApplyRunState() }

        // Allow the apply progress UI to render fully before heavy work begins.
        let shouldDelayForUI = await MainActor.run { self.showingApplyProgressSheet }
        if shouldDelayForUI {
            await Task.yield()
            await Task.yield()
            try? await Task.sleep(nanoseconds: 280_000_000)  // ~0.28s for sheet presentation + layout
        }

        await ConcurrentLogManager.shared.info(
            .filterApply, "Starting filter application process",
            metadata: ["platform": currentPlatform == .macOS ? "macOS" : "iOS"])

        // First, check for and download updates for enabled filters
        await MainActor.run {
            self.statusDescription = "Checking for updates..."
            self.applyProgressViewModel.updateStageDescription("Checking for updates...")
            self.applyProgressViewModel.updatePhaseCompletion(updating: false)  // Mark as active
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
                    self.applyProgressViewModel.updateStageDescription(
                        "Downloading \(updatedFilters.count) update(s)...")
                }

                await ConcurrentLogManager.shared.info(
                    .filterApply, "Found and downloading updates before applying",
                    metadata: ["count": "\(updatedFilters.count)"])

                _ = await filterUpdater.updateSelectedFilters(
                    updatedFilters,
                    progressCallback: { prog in
                        Task { @MainActor in
                            self.progress = prog * 0.1  // Use first 10% of progress for updates
                            self.applyProgressViewModel.updateProgress(Float(prog * 0.1))
                        }
                    })

                saveFilterListsSync()
            } else {
                await ConcurrentLogManager.shared.info(
                    .filterApply, "No updates available", metadata: [:])
            }
        }

        // Mark updating phase as complete
        await MainActor.run {
            self.applyProgressViewModel.updatePhaseCompletion(updating: true, scripts: false)
            self.statusDescription = "Applying filters...\n(This may take a while)"
            self.applyProgressViewModel.updateStageDescription("Applying filters...")
        }

        // Auto-update enabled userscripts as part of Apply Changes (helps YouTube, etc.).
        if let userScriptManager = filterUpdater.userScriptManager {
            let scriptsResult = await userScriptManager.autoUpdateEnabledUserScripts()
            await MainActor.run {
                self.applyProgressViewModel.updateScriptsUpdateResult(
                    updated: scriptsResult.updated,
                    failed: scriptsResult.failed
                )
                self.applyProgressViewModel.updatePhaseCompletion(scripts: true, reading: false)
            }
        } else {
            await MainActor.run {
                self.applyProgressViewModel.updateScriptsUpdateResult(updated: 0, failed: 0)
                self.applyProgressViewModel.updatePhaseCompletion(scripts: true, reading: false)
            }
        }

        let allSelectedFilters = await MainActor.run { self.filterLists.filter { $0.isSelected } }

        if allSelectedFilters.isEmpty {
            await MainActor.run {
                self.statusDescription =
                    "No filter lists selected. Clearing rules from all extensions."
            }
            await ConcurrentLogManager.shared.info(
                .filterApply, "No filters selected - clearing all extensions", metadata: [:])

            // Perform heavy operations on background thread
            let currentPlatform = self.currentPlatform

            await Task.detached {
                // Clear the filter engine when no filters are selected
                ContentBlockerService.clearFilterEngine(
                    groupIdentifier: GroupIdentifier.shared.value)

                // Clear rules for all relevant extensions
                let platformTargets = ContentBlockerTargetManager.shared.allTargets(
                    forPlatform: currentPlatform)
                for targetInfo in platformTargets {
                    _ = ContentBlockerService.saveContentBlocker(
                        jsonRules: "[]",
                        groupIdentifier: GroupIdentifier.shared.value,
                        targetRulesFilename: targetInfo.rulesFilename
                    )
                    _ = await self.reloadContentBlockerWithRetry(targetInfo: targetInfo)
                }
            }.value

            await MainActor.run {
                self.isLoading = false
                self.showingApplyProgressSheet = false
                self.hasUnappliedChanges = false
                self.lastRuleCount = 0
                self.ruleCountsByExtension.removeAll()
                self.extensionsApproachingLimit.removeAll()
                self.saveRuleCounts()
            }
            return
        }

        let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: self.currentPlatform)

        let filtersByTargetInfo = ContentBlockerMappingService.distribute(
            selectedFilters: allSelectedFilters,
            across: platformTargets
        )

        let totalFiltersCount = platformTargets.count
        await MainActor.run {
            self.sourceRulesCount = allSelectedFilters.reduce(0) { $0 + ($1.sourceRuleCount ?? 0) }

            // Update ViewModel
            self.applyProgressViewModel.updateProcessedCount(0, total: totalFiltersCount)
            self.applyProgressViewModel.updateConvertingDone(0)
            self.applyProgressViewModel.updateReloadingDone(0)
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
        var conversionMetrics: [TargetConversionMetrics] = []

        await MainActor.run {
            self.processedFiltersCount = 0  // Use this to track processed targets for progress

            // Update ViewModel phase
            self.applyProgressViewModel.updatePhaseCompletion(reading: true, converting: false)
            self.applyProgressViewModel.updateConvertingDone(0)
        }

        await MainActor.run {
            self.ruleCountsByExtension = [:]
            self.extensionsApproachingLimit = []
        }

        // Collect advanced rules by target bundle ID (single storage)
        var advancedRulesByTarget: [String: String] = [:]  // bundleIdentifier -> advanced rules

        let ruleLimit = 150_000
        let warningThreshold = Int(Double(ruleLimit) * 0.8)  // 80% threshold

        let disabledSites = self.dataManager.disabledSites

        for targetInfo in platformTargets {
            let filters = filtersByTargetInfo[targetInfo] ?? []
            let blockerName = targetInfo.displayName
            let conversionStart = Date()

            await MainActor.run {
                self.applyProgressViewModel.updateStageDescription("Converting \(blockerName)…")
            }

            // Yield to prevent main thread starvation on iOS
            await Task.yield()

            // Reuse cached conversion output when assigned filter inputs are unchanged.
            let conversionResult = await Task.detached {
                Self.convertOrReuseTargetRules(
                    filters: filters,
                    targetInfo: targetInfo,
                    disabledSites: disabledSites,
                    groupIdentifier: GroupIdentifier.shared.value
                )
            }.value

            let ruleCountForThisTarget = conversionResult.safariRulesCount

            if let advancedRulesText = conversionResult.advancedRulesText, !advancedRulesText.isEmpty {
                advancedRulesByTarget[targetInfo.bundleIdentifier] = advancedRulesText
            } else {
                advancedRulesByTarget.removeValue(forKey: targetInfo.bundleIdentifier)
            }

            let advancedCount =
                conversionResult.advancedRulesText?.isEmpty == false
                ? conversionResult.advancedRulesText!.components(separatedBy: .newlines).count
                : 0

            conversionMetrics.append(
                TargetConversionMetrics(
                    blockerName: blockerName,
                    filterCount: filters.count,
                    safariRules: ruleCountForThisTarget,
                    advancedRules: advancedCount,
                    reusedCachedBase: conversionResult.reusedCachedBase,
                    durationMs: Int(Date().timeIntervalSince(conversionStart) * 1000)
                )
            )

            await MainActor.run {
                self.processedFiltersCount += 1
                self.progress = Float(self.processedFiltersCount) / Float(totalFiltersCount) * 0.7  // Up to 70% for conversion
                self.applyProgressViewModel.updateProgress(self.progress)
                self.applyProgressViewModel.updateConvertingDone(self.processedFiltersCount)
                self.applyProgressViewModel.updateCurrentFilter(blockerName)
                self.ruleCountsByExtension[targetInfo.bundleIdentifier] = ruleCountForThisTarget

                if ruleCountForThisTarget >= warningThreshold && ruleCountForThisTarget < ruleLimit {
                    self.extensionsApproachingLimit.insert(targetInfo.bundleIdentifier)
                } else {
                    self.extensionsApproachingLimit.remove(targetInfo.bundleIdentifier)
                }
            }

            if ruleCountForThisTarget > ruleLimit {
                await ConcurrentLogManager.shared.error(
                    .filterApply, "Rule limit exceeded for blocker",
                    metadata: [
                        "blocker": blockerName,
                        "bundleId": targetInfo.bundleIdentifier,
                        "ruleCount": "\(ruleCountForThisTarget)",
                        "ruleLimit": "\(ruleLimit)",
                    ]
                )

                await MainActor.run {
                    self.hasError = true
                    self.statusDescription =
                        "One or more content blockers exceeded Safari's \(ruleLimit.formatted()) rule limit. Disable some filter lists and try again."
                }
            }

            overallSafariRulesApplied += ruleCountForThisTarget
        }
        await MainActor.run {
            self.lastRuleCount = overallSafariRulesApplied
            self.lastConversionTime = String(
                format: "%.2fs", Date().timeIntervalSince(overallConversionStartTime))
            self.progress = 0.7

            // Update ViewModel - conversion complete
            self.applyProgressViewModel.updateProgress(self.progress)
            self.applyProgressViewModel.updatePhaseCompletion(converting: true, saving: false)
        }
        await ConcurrentLogManager.shared.info(
            .filterApply, "Conversion phase summary",
            metadata: [
                "targets": "\(conversionMetrics.count)",
                "assignedFilters": "\(conversionMetrics.reduce(0) { $0 + $1.filterCount })",
                "cacheHits": "\(conversionMetrics.filter { $0.reusedCachedBase }.count)",
                "cacheMisses": "\(conversionMetrics.filter { !$0.reusedCachedBase }.count)",
                "totalRules": "\(conversionMetrics.reduce(0) { $0 + $1.safariRules })",
                "advancedRules": "\(conversionMetrics.reduce(0) { $0 + $1.advancedRules })",
                "conversionTime": await MainActor.run { self.lastConversionTime },
                "avgTargetMs": conversionMetrics.isEmpty
                    ? "0"
                    : "\(conversionMetrics.reduce(0) { $0 + $1.durationMs } / conversionMetrics.count)",
                "slowestTarget": conversionMetrics.max(by: { $0.durationMs < $1.durationMs })
                    .map { "\($0.blockerName)@\($0.durationMs)ms" } ?? "n/a",
            ])

        // Reloading phase - reload all content blockers FIRST before building advanced engine
        await MainActor.run {
            self.processedFiltersCount = 0

            // Update ViewModel - starting reload phase
            self.applyProgressViewModel.updatePhaseCompletion(saving: true, reloading: false)
            self.applyProgressViewModel.updateStageDescription("Reloading Safari extensions...")
            self.applyProgressViewModel.updateProcessedCount(0, total: totalFiltersCount)
            self.applyProgressViewModel.updateReloadingDone(0)
            self.applyProgressViewModel.updateCurrentFilter("")
        }

        let overallReloadStartTime = Date()
        let reloadSummary = await reloadContentBlockersInParallel(platformTargets, totalCount: totalFiltersCount)
        let allReloadsSuccessful = reloadSummary.allSuccessful

        // Log reload summary
        await MainActor.run {
            self.lastReloadTime = String(
                format: "%.2fs", Date().timeIntervalSince(overallReloadStartTime))
        }

        let failedReloads = reloadSummary.metrics.filter { !$0.success }
        let retriedReloads = reloadSummary.metrics.filter { $0.attempts > 1 }
        let totalReloadAttempts = reloadSummary.metrics.reduce(0) { $0 + $1.attempts }
        let reloadMetadata: [String: String] = [
            "targets": "\(reloadSummary.metrics.count)",
            "failedTargets": "\(failedReloads.count)",
            "retriedTargets": "\(retriedReloads.count)",
            "totalAttempts": "\(totalReloadAttempts)",
            "avgAttempts": reloadSummary.metrics.isEmpty ? "0" : String(
                format: "%.2f",
                Double(totalReloadAttempts) / Double(reloadSummary.metrics.count)
            ),
            "reloadTime": await MainActor.run { self.lastReloadTime },
            "slowestTarget": reloadSummary.metrics.max(by: { $0.durationMs < $1.durationMs })
                .map { "\($0.blockerName)@\($0.durationMs)ms" } ?? "n/a",
            "failedNames": failedReloads.prefix(3).map(\.blockerName).joined(separator: ","),
        ]

        if allReloadsSuccessful {
            await ConcurrentLogManager.shared.info(
                .filterApply, "Reload phase summary",
                metadata: reloadMetadata)
        } else {
            await ConcurrentLogManager.shared.warning(
                .filterApply,
                "Reload phase had failures; continuing with advanced rules processing",
                metadata: reloadMetadata)
        }

        // Small delay before building advanced engine to let system recover from reloads
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms delay

        // NOW build the combined filter engine AFTER all content blockers are reloaded
        await MainActor.run {
            self.progress = 0.9

            // Update ViewModel
            self.applyProgressViewModel.updateProgress(self.progress)
            self.applyProgressViewModel.updatePhaseCompletion(reloading: true)
        }

        if !advancedRulesByTarget.isEmpty {
            await MainActor.run {
                self.applyProgressViewModel.updateStageDescription("Building combined filter engine...")
            }

            // Run engine building on background thread
            await Task.detached {
                let combinedAdvancedRules = advancedRulesByTarget.values.joined(separator: "\n")
                let totalLines = combinedAdvancedRules.components(separatedBy: "\n").count
                await ConcurrentLogManager.shared.info(
                    .filterApply, "Building filter engine",
                    metadata: [
                        "targetCount": "\(advancedRulesByTarget.count)",
                        "totalLines": "\(totalLines)",
                    ])

                ContentBlockerService.buildCombinedFilterEngine(
                    combinedAdvancedRules: combinedAdvancedRules,
                    groupIdentifier: GroupIdentifier.shared.value
                )
            }.value

        } else {
            await ConcurrentLogManager.shared.debug(
                .filterApply, "No advanced rules found, clearing filter engine", metadata: [:])
            // Run on background thread
            await Task.detached {
                ContentBlockerService.clearFilterEngine(
                    groupIdentifier: GroupIdentifier.shared.value)
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
                self.statusDescription =
                    "Applied rules to \(filtersByTargetInfo.keys.count) blocker(s). Total: \(overallSafariRulesApplied) Safari rules. Advanced engine: \(advancedRulesByTarget.isEmpty ? "cleared" : "\(advancedRulesByTarget.count) targets combined")."
                self.hasUnappliedChanges = false
            }
        } else if !hasErrorValue {  // Implies reload issue was the only problem
            await MainActor.run {
                self.statusDescription =
                    "Converted rules, but one or more extensions failed to reload after 5 attempts. Advanced engine: \(advancedRulesByTarget.isEmpty ? "cleared" : "\(advancedRulesByTarget.count) targets combined")."
            }
        }  // If hasError was already true, statusDescription would reflect the earlier error.

        await MainActor.run {
            self.isLoading = false

            let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: self.currentPlatform)
            let ruleCountsByBlocker = Dictionary(
                uniqueKeysWithValues: platformTargets.map { target in
                    (target.displayName, self.ruleCountsByExtension[target.bundleIdentifier] ?? 0)
                }
            )
            let blockersApproachingLimit = Set(
                platformTargets
                    .filter { self.extensionsApproachingLimit.contains($0.bundleIdentifier) }
                    .map { $0.displayName }
            )

            // Update ViewModel with final statistics
            self.applyProgressViewModel.updateStatistics(
                sourceRules: self.sourceRulesCount,
                safariRules: self.lastRuleCount,
                conversionTime: self.lastConversionTime,
                reloadTime: self.lastReloadTime,
                ruleCountsByBlocker: ruleCountsByBlocker,
                blockersApproachingLimit: blockersApproachingLimit,
                statusMessage: self.statusDescription
            )
            self.applyProgressViewModel.updateIsLoading(false)
        }
        // Keep showingApplyProgressSheet = true until user dismisses it if it was successful or had errors.
        // Or: showingApplyProgressSheet = false // if you want it to auto-dismiss on error

        saveFilterListsSync()  // Save any state like sourceRuleCount if updated

        // Save rule counts to UserDefaults for next app launch
        saveRuleCounts()

        // Final summary log
        let hasErrorValueForLog = await MainActor.run { self.hasError }
        let statusDesc = await MainActor.run { self.statusDescription }

        if allReloadsSuccessful && !hasErrorValueForLog {
            await ConcurrentLogManager.shared.info(
                .filterApply, "Process completed successfully", metadata: ["status": statusDesc])
        } else if !hasErrorValueForLog {
            await ConcurrentLogManager.shared.warning(
                .filterApply, "Process completed with reload issues",
                metadata: ["status": statusDesc])
        } else {
            await ConcurrentLogManager.shared.error(
                .filterApply, "Process completed with errors", metadata: ["status": statusDesc])
        }
    }

    private func prepareApplyRunState() {
        isLoading = true
        hasError = false
        progress = 0
        statusDescription = "Checking for updates..."

        applyProgressViewModel.reset()
        applyProgressViewModel.updateIsLoading(true)
        applyProgressViewModel.updateProgress(0)

        sourceRulesCount = 0
        processedFiltersCount = 0
    }

    @MainActor
    public func downloadAndApplyFilters(filters: [FilterList], progress: @escaping (Float) -> Void)
        async
    {
        isLoading = true
        hasError = false
        statusDescription = "Downloading filter lists..."
        progress(0)

        // Download selected filters using existing updater logic
        let _ = await filterUpdater.updateSelectedFilters(
            filters,
            progressCallback: { prog in
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
            Task {
                await ConcurrentLogManager.shared.info(
                    .autoUpdate, "No updates available", metadata: [:])
            }
        }

        isLoading = false
    }

    func updateSelectedFilters(_ selectedFilters: [FilterList]) async {  // From UpdatePopupView
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
            self.prepareApplyRunState()
            showingApplyProgressSheet = true
        }

        // Automatically apply changes after download
        await applyChanges()
    }

    private func downloadMissingItemsSilently() async {
        for filter in missingFilters {
            if await filterUpdater.fetchAndProcessFilter(filter) {
                await MainActor.run { self.missingFilters.removeAll { $0.id == filter.id } }
            }
        }

        if let userScriptManager = filterUpdater.userScriptManager {
            for script in missingUserScripts where script.url != nil {
                let downloaded = await userScriptManager.downloadUserScript(script)
                if downloaded {
                    await MainActor.run { self.missingUserScripts.removeAll { $0.id == script.id } }
                }
            }
        }

        saveFilterListsSync()
    }

    // MARK: - List Management
    func addFilterList(name: String, urlString: String, category: FilterListCategory = .custom, hasUserProvidedName: Bool = false) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            statusDescription = "Invalid URL provided: \(urlString)"
            hasError = true
            Task {
                await ConcurrentLogManager.shared.error(
                    .system, "Invalid URL provided for new filter list",
                    metadata: ["url": urlString])
            }
            return
        }

        if filterLists.contains(where: { $0.url == url }) {
            statusDescription = "Filter list with this URL already exists: \(url.absoluteString)"
            hasError = true
            Task {
                await ConcurrentLogManager.shared.error(
                    .system, "Filter list with URL already exists",
                    metadata: ["url": url.absoluteString])
            }
            return
        }

        if category == .custom, CloudSyncManager.shared.isEnabled {
            CloudSyncManager.shared.clearDeletedCustomListURL(url.absoluteString)
        }

        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newFilter = FilterList(
            id: UUID(),
            name: newName.isEmpty ? (url.host ?? "Custom Filter") : newName,
            url: url,
            category: category,
            isCustom: true,
            isSelected: true,
            description: "User-added filter list.",
            sourceRuleCount: nil,
            hasUserProvidedName: hasUserProvidedName)
        addCustomFilterList(newFilter)
    }

    func addUserList(name: String, description: String? = nil, content: String, isSelected: Bool = true) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            statusDescription = "Title is required."
            hasError = true
            return
        }

        guard !trimmedContent.isEmpty else {
            statusDescription = "User list is empty."
            hasError = true
            return
        }

        let lower = trimmedContent.lowercased()
        if lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html") {
            statusDescription = "That doesn’t look like a filter list."
            hasError = true
            return
        }

        let id = UUID()
        let url = URL(string: "wblock://userlist/\(id.uuidString)")!
        let finalName = trimmedName

        let newFilter = FilterList(
            id: id,
            name: finalName,
            url: url,
            category: .custom,
            isCustom: true,
            isSelected: isSelected,
            description: trimmedDescription?.isEmpty == false ? trimmedDescription! : "User list.",
            sourceRuleCount: Self.countRulesInUserListContent(trimmedContent)
        )

        guard let destinationURL = loader.localFileURL(for: newFilter) else {
            statusDescription = "Failed to access shared storage."
            hasError = true
            return
        }

        do {
            try trimmedContent.write(to: destinationURL, atomically: true, encoding: .utf8)
        } catch {
            statusDescription = "Failed to save user list."
            hasError = true
            Task {
                await ConcurrentLogManager.shared.error(
                    .system,
                    "Failed saving user list",
                    metadata: ["error": error.localizedDescription]
                )
            }
            return
        }

        addCustomFilterListWithoutFetch(newFilter)
        hasUnappliedChanges = true
        statusDescription = "✅ User list added. Apply changes to enable it."
        hasError = false
    }

    func addUserListFromFile(_ fileURL: URL, nameOverride: String?, description: String? = nil, isSelected: Bool = true) {
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let name = nameOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            addUserList(name: name, description: description, content: content, isSelected: isSelected)
        } catch {
            statusDescription = "Failed to read file."
            hasError = true
            Task {
                await ConcurrentLogManager.shared.error(
                    .system,
                    "Failed reading user list file",
                    metadata: ["error": error.localizedDescription]
                )
            }
        }
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

            filterLists.append(newFilterToAdd)
            saveFilterListsSync()

            Task {
                await ConcurrentLogManager.shared.info(
                    .system, "Added custom filter", metadata: ["filter": newFilterToAdd.name])
            }

            Task {
                let success = await filterUpdater.fetchAndProcessFilter(newFilterToAdd)
                if success {
                    let currentName = await MainActor.run {
                        self.filterLists.first(where: { $0.id == newFilterToAdd.id })?.name ?? newFilterToAdd.name
                    }
                    await ConcurrentLogManager.shared.info(
                        .filterUpdate, "Successfully downloaded custom filter",
                        metadata: ["filter": currentName])
                    await MainActor.run {
                        self.hasUnappliedChanges = true
                        self.statusDescription =
                            "✅ Filter '\(currentName)' added successfully. Apply changes to enable it."
                        self.hasError = false
                    }
                    saveFilterListsSync()
                } else {
                    await ConcurrentLogManager.shared.error(
                        .filterUpdate, "Failed to download custom filter",
                        metadata: ["filter": newFilterToAdd.name])
                    await MainActor.run {
                        removeCustomFilterList(newFilterToAdd)
                        self.statusDescription =
                            "❌ Failed to add filter. The URL may be invalid or the content is not a valid filter list."
                        self.hasError = true
                    }
                }
            }
        } else {
            Task {
                await ConcurrentLogManager.shared.warning(
                    .system, "Custom filter with URL already exists",
                    metadata: ["url": filter.url.absoluteString])
            }
        }
    }

    private func addCustomFilterListWithoutFetch(_ filter: FilterList) {
        guard !customFilterLists.contains(where: { $0.url == filter.url }) else { return }

        customFilterLists.append(filter)
        filterLists.append(filter)
        saveFilterListsSync()

        Task {
            await ConcurrentLogManager.shared.info(
                .system, "Added user list",
                metadata: ["filter": filter.name, "url": filter.url.absoluteString]
            )
        }
    }

    func removeCustomFilterList(_ filter: FilterList) {
        if filter.isCustom, CloudSyncManager.shared.isEnabled {
            CloudSyncManager.shared.recordDeletedCustomListURL(filter.url.absoluteString)
        }

        customFilterLists.removeAll { $0.id == filter.id }

        filterLists.removeAll { $0.id == filter.id }
        saveFilterListsSync()

        if let containerURL = loader.getSharedContainerURL() {
            let idFileURL = containerURL.appendingPathComponent(
                ContentBlockerIncrementalCache.localFilename(for: filter)
            )
            try? FileManager.default.removeItem(at: idFileURL)
            // Clean up any legacy name-based file.
            let legacyFileURL = containerURL.appendingPathComponent("\(filter.name).txt")
            try? FileManager.default.removeItem(at: legacyFileURL)
        }
        Task {
            await ConcurrentLogManager.shared.info(
                .system, "Removed custom filter", metadata: ["filter": filter.name])
        }
        hasUnappliedChanges = true
    }

    nonisolated private static func countRulesInUserListContent(_ content: String) -> Int {
        var count = 0
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return }
            if trimmed.hasPrefix("!") { return }
            if trimmed.hasPrefix("[") { return }
            count += 1
        }
        return count
    }

    func updateCustomFilterListName(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let index = filterLists.firstIndex(where: { $0.id == id && $0.isCustom }) else {
            return
        }

        // Avoid confusing duplicate names in the UI.
        if filterLists.contains(where: {
            $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            statusDescription = "A filter list with this name already exists."
            hasError = true
            return
        }

        filterLists[index].name = trimmed
        filterLists[index].hasUserProvidedName = true
        if let customIndex = customFilterLists.firstIndex(where: { $0.id == id }) {
            customFilterLists[customIndex].name = trimmed
            customFilterLists[customIndex].hasUserProvidedName = true
        }
        saveFilterListsSync()

        Task {
            await ConcurrentLogManager.shared.info(
                .system, "Renamed custom filter list",
                metadata: ["filterId": id.uuidString, "name": trimmed]
            )
        }
    }

    func updateUserList(id: UUID, name: String, description: String, content: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            statusDescription = "Title is required."
            hasError = true
            return
        }

        guard !trimmedContent.isEmpty else {
            statusDescription = "User list is empty."
            hasError = true
            return
        }

        guard let index = filterLists.firstIndex(where: { $0.id == id && $0.isCustom }) else {
            statusDescription = "User list not found."
            hasError = true
            return
        }

        let filter = filterLists[index]
        let isInlineUserList = filter.url.scheme?.lowercased() == "wblock"
            && filter.url.host?.lowercased() == "userlist"
        guard isInlineUserList else {
            statusDescription = "Only pasted user lists can be edited."
            hasError = true
            return
        }

        if filterLists.contains(where: {
            $0.id != id && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
        }) {
            statusDescription = "A filter list with this name already exists."
            hasError = true
            return
        }

        loader.migrateCustomFilterFileIfNeeded(filter)
        guard let destinationURL = loader.localFileURL(for: filter) else {
            statusDescription = "Failed to access shared storage."
            hasError = true
            return
        }

        do {
            try trimmedContent.write(to: destinationURL, atomically: true, encoding: .utf8)
        } catch {
            statusDescription = "Failed to save user list."
            hasError = true
            Task {
                await ConcurrentLogManager.shared.error(
                    .system,
                    "Failed saving user list edits",
                    metadata: ["error": error.localizedDescription]
                )
            }
            return
        }

        filterLists[index].name = trimmedName
        filterLists[index].description = trimmedDescription
        filterLists[index].sourceRuleCount = Self.countRulesInUserListContent(trimmedContent)

        if let customIndex = customFilterLists.firstIndex(where: { $0.id == id }) {
            customFilterLists[customIndex].name = trimmedName
            customFilterLists[customIndex].description = trimmedDescription
            customFilterLists[customIndex].sourceRuleCount = filterLists[index].sourceRuleCount
        }

        saveFilterListsSync()
        hasUnappliedChanges = true
        statusDescription = "✅ User list updated. Apply changes to enable it."
        hasError = false
    }

    func revertToRecommendedFilters() async {
        for index in filterLists.indices {
            filterLists[index].isSelected = false
        }

        #if os(iOS)
            let essentialFilters = [
                "AdGuard Base Filter",
                "EasyPrivacy",
            ]
        #else
            let essentialFilters = [
                "AdGuard Base Filter",
                "AdGuard Tracking Protection Filter",
                "EasyPrivacy",
                "Online Security Filter",
            ]
        #endif

        for index in filterLists.indices {
            filterLists[index].isSelected = essentialFilters.contains(filterLists[index].name)
        }

        saveFilterListsSync()
        hasUnappliedChanges = false
        statusDescription = "Reverted to essential filters to stay under Safari's 150k rule limit."

        await MainActor.run {
            self.prepareApplyRunState()
            showingApplyProgressSheet = true
        }
        await applyChanges()
    }

    // Set the UserScriptManager for the filter updater
    public func setUserScriptManager(_ userScriptManager: UserScriptManager) {
        filterUpdater.userScriptManager = userScriptManager
    }

    /// Memory-efficient conversion that combines filter files using streaming I/O
    nonisolated private static func convertFiltersMemoryEfficient(
        filters: [FilterList],
        targetInfo: ContentBlockerTargetInfo,
        disabledSites: [String],
        groupIdentifier: String
    ) -> (safariRulesCount: Int, advancedRulesText: String?) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
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

            var hasher = SHA256()
            let newlineData = Data("\n".utf8)

            // Stream each filter file directly to temp file
            for filter in filters {
                let fileURL = containerURL.appendingPathComponent(
                    ContentBlockerIncrementalCache.localFilename(for: filter)
                )
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try Self.appendFileContentsToCombinedStream(
                        sourceURL: fileURL,
                        destinationHandle: fileHandle,
                        hasher: &hasher,
                        newlineData: newlineData
                    )
                } else if filter.isCustom {
                    // Backward compatibility: legacy custom filters were stored as "<name>.txt".
                    let legacyURL = containerURL.appendingPathComponent("\(filter.name).txt")
                    if FileManager.default.fileExists(atPath: legacyURL.path) {
                        try Self.appendFileContentsToCombinedStream(
                            sourceURL: legacyURL,
                            destinationHandle: fileHandle,
                            hasher: &hasher,
                            newlineData: newlineData
                        )
                    }
                }
            }

            let digest = hasher.finalize()
            let rulesSHA256Hex = digest.map { String(format: "%02x", $0) }.joined()

            return ContentBlockerService.convertFilterFromFile(
                rulesFileURL: tempURL,
                rulesSHA256Hex: rulesSHA256Hex,
                groupIdentifier: groupIdentifier,
                targetRulesFilename: targetInfo.rulesFilename,
                disabledSites: disabledSites
            )

        } catch {
            Task {
                await ConcurrentLogManager.shared.error(
                    .filterApply, "Error in memory-efficient conversion",
                    metadata: ["error": "\(error)"])
            }
            return (safariRulesCount: 0, advancedRulesText: nil)
        }
    }

    private struct TargetConversionOutcome {
        let safariRulesCount: Int
        let advancedRulesText: String?
        let reusedCachedBase: Bool
    }

    private struct TargetConversionMetrics {
        let blockerName: String
        let filterCount: Int
        let safariRules: Int
        let advancedRules: Int
        let reusedCachedBase: Bool
        let durationMs: Int
    }

    private struct ReloadAttemptResult {
        let success: Bool
        let attempts: Int
        let durationMs: Int
    }

    private struct TargetReloadMetrics {
        let blockerName: String
        let success: Bool
        let attempts: Int
        let durationMs: Int
    }

    private struct ReloadPhaseSummary {
        let allSuccessful: Bool
        let metrics: [TargetReloadMetrics]
    }

    nonisolated private static func convertOrReuseTargetRules(
        filters: [FilterList],
        targetInfo: ContentBlockerTargetInfo,
        disabledSites: [String],
        groupIdentifier: String
    ) -> TargetConversionOutcome {
        let rulesFilename = targetInfo.rulesFilename
        let currentSignature = ContentBlockerIncrementalCache.computeInputSignature(
            filters: filters,
            groupIdentifier: groupIdentifier
        )
        let storedSignature = ContentBlockerIncrementalCache.loadInputSignature(
            targetRulesFilename: rulesFilename,
            groupIdentifier: groupIdentifier
        )

        if let currentSignature,
            currentSignature == storedSignature,
            ContentBlockerIncrementalCache.hasBaseRulesCache(
                targetRulesFilename: rulesFilename,
                groupIdentifier: groupIdentifier
            )
        {
            let fastUpdate = ContentBlockerService.fastUpdateDisabledSites(
                groupIdentifier: groupIdentifier,
                targetRulesFilename: rulesFilename,
                disabledSites: disabledSites
            )
            let cachedAdvancedRules = ContentBlockerIncrementalCache.loadCachedAdvancedRules(
                targetRulesFilename: rulesFilename,
                groupIdentifier: groupIdentifier
            )
            let trimmedAdvanced = cachedAdvancedRules?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return TargetConversionOutcome(
                safariRulesCount: fastUpdate.safariRulesCount,
                advancedRulesText: (trimmedAdvanced?.isEmpty == false) ? trimmedAdvanced : nil,
                reusedCachedBase: true
            )
        }

        let conversion = convertFiltersMemoryEfficient(
            filters: filters,
            targetInfo: targetInfo,
            disabledSites: disabledSites,
            groupIdentifier: groupIdentifier
        )

        if let currentSignature {
            ContentBlockerIncrementalCache.saveInputSignature(
                currentSignature,
                targetRulesFilename: rulesFilename,
                groupIdentifier: groupIdentifier
            )
        }

        return TargetConversionOutcome(
            safariRulesCount: conversion.safariRulesCount,
            advancedRulesText: conversion.advancedRulesText,
            reusedCachedBase: false
        )
    }

    nonisolated private static func appendFileContentsToCombinedStream(
        sourceURL: URL,
        destinationHandle: FileHandle,
        hasher: inout SHA256,
        newlineData: Data,
        chunkSize: Int = 64 * 1024
    ) throws {
        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? sourceHandle.close() }

        while true {
            let chunk = try sourceHandle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            try destinationHandle.write(contentsOf: chunk)
        }

        hasher.update(data: newlineData)
        try destinationHandle.write(contentsOf: newlineData)
    }

    private func reloadContentBlockersInParallel(_ targets: [ContentBlockerTargetInfo], totalCount: Int) async -> ReloadPhaseSummary {
        #if os(macOS)
        let maxConcurrent = 3
        #else
        let maxConcurrent = 2
        #endif
        var allSuccessful = true
        var metrics: [TargetReloadMetrics] = []

        var iterator = targets.makeIterator()

        await withTaskGroup(of: (ContentBlockerTargetInfo, ReloadAttemptResult).self) { group in
            func startNext() {
                guard let target = iterator.next() else { return }

                group.addTask {
                    let reloadResult = await Self.reloadWithRetry(
                        identifier: target.bundleIdentifier,
                        maxRetries: 5
                    )
                    return (target, reloadResult)
                }
            }

            for _ in 0..<min(maxConcurrent, targets.count) {
                startNext()
            }

            while let (target, reloadResult) = await group.next() {
                let name = target.displayName

                await MainActor.run {
                    self.processedFiltersCount += 1
                    self.applyProgressViewModel.updateReloadingDone(self.processedFiltersCount)
                    self.applyProgressViewModel.updateCurrentFilter(name)

                    self.progress =
                        0.7 + (Float(self.processedFiltersCount) / Float(max(1, totalCount)) * 0.2)
                    self.applyProgressViewModel.updateProgress(self.progress)

                    if !reloadResult.success {
                        if !self.hasError {
                            self.statusDescription = "Failed to reload \(name)."
                        }
                        self.hasError = true
                    }
                }

                metrics.append(
                    TargetReloadMetrics(
                        blockerName: name,
                        success: reloadResult.success,
                        attempts: reloadResult.attempts,
                        durationMs: reloadResult.durationMs
                    )
                )
                allSuccessful = allSuccessful && reloadResult.success
                startNext()
            }
        }

        return ReloadPhaseSummary(allSuccessful: allSuccessful, metrics: metrics)
    }

    nonisolated private static func reloadWithRetry(
        identifier: String,
        maxRetries: Int
    ) async -> ReloadAttemptResult {
        let start = Date()
        for attempt in 1...maxRetries {
            let result = await ContentBlockerService.reloadContentBlocker(withIdentifier: identifier)
            if case .success = result {
                return ReloadAttemptResult(
                    success: true,
                    attempts: attempt,
                    durationMs: Int(Date().timeIntervalSince(start) * 1000)
                )
            }

            if attempt < maxRetries {
                // Back off quickly; WKErrorDomain error 6 is often transient right after writes.
                let delayMs = min(200 * attempt, 1500)
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
        }
        return ReloadAttemptResult(
            success: false,
            attempts: maxRetries,
            durationMs: Int(Date().timeIntervalSince(start) * 1000)
        )
    }
}
