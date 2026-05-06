//
//  AppFilterManager.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

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
    @Published var statusDescription: String = LocalizedStrings.text("Ready.", comment: "Filter manager idle status")
    @Published var lastConversionTime: String = LocalizedStrings.text("N/A", comment: "Unavailable metric placeholder")
    @Published var lastReloadTime: String = LocalizedStrings.text("N/A", comment: "Unavailable metric placeholder")
    @Published var lastRuleCount: Int = 0
    @Published var hasError: Bool = false
    @Published var progress: Float = 0
    var missingFilters: [FilterList] = []
    var missingUserScripts: [UserScript] = []
    @Published var availableUpdates: [FilterList] = []
    @Published var availableScriptUpdates: [UserScript] = []
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
    @Published var ruleLimitWarningTitle = ""

    // Performance tracking
    @Published var lastFastUpdateTime: String = LocalizedStrings.text("N/A", comment: "Unavailable metric placeholder")
    @Published var fastUpdateCount: Int = 0

    // New ViewModel-based progress tracking
    @Published var applyProgressViewModel = ApplyChangesViewModel()

    // Internal counters used for apply-run summary/progress math.
    var sourceRulesCount: Int = 0
    var processedFiltersCount: Int = 0
    @Published var currentPlatform: Platform

    // Dependencies
    let loader: FilterListLoader
    private(set) var filterUpdater: FilterListUpdater
    let logManager: ConcurrentLogManager
    let dataManager = ProtobufDataManager.shared

    // Per-site disable tracking
    var lastKnownDisabledSites: [String] = []
    var disabledSitesDirectoryMonitor: DispatchSourceFileSystemObject?
    var disabledSitesDirectoryFileDescriptor: CInt = -1
    var pendingDisabledSitesCheckTask: Task<Void, Never>?
    let disabledSitesMonitorQueue = DispatchQueue(
        label: "skula.wBlock.disabled-sites-monitor",
        qos: .utility
    )

    var customFilterLists: [FilterList] {
        filterLists.filter(\.isCustom)
    }

    private enum UBlockMigrationState: String {
        case notStarted
        case catalogMigrated
        case applyStarted
        case applySucceeded
        case applyFailed
    }

    private enum UBlockMigrationKeys {
        static let targetVersion = 1
    }

    private var appliedSelectedFilterIDs: Set<UUID> = []
    private var appliedCustomFilterKeys: Set<String> = []
    private var hasPendingSelectionChanges = false
    private var hasPendingNonSelectionChanges = false

    private var selectedFilterIDs: Set<UUID> {
        Set(filterLists.filter(\.isSelected).map(\.id))
    }

    private var customFilterKeys: Set<String> {
        Set(filterLists.filter(\.isCustom).map(\.url.absoluteString))
    }

    var filterListIndexByID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: filterLists.enumerated().map { ($1.id, $0) })
    }

    func refreshPendingSelectionChanges() {
        hasPendingSelectionChanges = selectedFilterIDs != appliedSelectedFilterIDs
        refreshHasUnappliedChanges()
    }

    func refreshPendingChanges() {
        hasPendingSelectionChanges =
            selectedFilterIDs != appliedSelectedFilterIDs
            || customFilterKeys != appliedCustomFilterKeys
        refreshHasUnappliedChanges()
    }

    func markNonSelectionChangesPending() {
        hasPendingNonSelectionChanges = true
        refreshHasUnappliedChanges()
    }

    func markCurrentStateApplied() {
        appliedSelectedFilterIDs = selectedFilterIDs
        appliedCustomFilterKeys = customFilterKeys
        hasPendingSelectionChanges = false
        hasPendingNonSelectionChanges = false
        hasUnappliedChanges = false
    }

    private func refreshHasUnappliedChanges() {
        hasUnappliedChanges = hasPendingSelectionChanges || hasPendingNonSelectionChanges
    }

    // Save filter lists
    func saveFilterLists() async {
        // Use existing updateFilterLists method from ProtobufDataManager+Extensions
        await dataManager.updateFilterLists(filterLists)
    }

    var pendingSaveTask: Task<Void, Never>?

    func saveFilterListsCoalesced() {
        pendingSaveTask?.cancel()
        let delay: UInt64 = 50_000_000
        var task: Task<Void, Never>?
        task = Task { @MainActor [weak self] in
            defer {
                if let self, let task, self.pendingSaveTask == task {
                    self.pendingSaveTask = nil
                }
            }
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await self.saveFilterLists()
        }
        pendingSaveTask = task
    }

    func flushPendingSave() {
        guard pendingSaveTask != nil else { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        Task { await saveFilterLists() }
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
        statusDescription = LocalizedStrings.text("Resetting…", comment: "Filter manager reset status")
        markCurrentStateApplied()
        showingApplyProgressSheet = false
        showingUpdatePopup = false
        missingFilters = []
        availableUpdates = []
        availableScriptUpdates = []
        ruleCountsByExtension = [:]
        extensionsApproachingLimit = []
        showingRuleLimitWarningAlert = false
        ruleLimitWarningMessage = ""
        ruleLimitWarningTitle = ""
        lastRuleCount = 0
        lastFastUpdateTime = LocalizedStrings.text("N/A", comment: "Unavailable metric placeholder")
        fastUpdateCount = 0
        sourceRulesCount = 0
        processedFiltersCount = 0

        filterLists = []
        markCurrentStateApplied()

        let defaultLists = loader.getDefaultFilterLists()
        filterLists = defaultLists
        markCurrentStateApplied()
        saveFilterListsCoalesced()

        await dataManager.updateRuleCounts(
            lastRuleCount: 0,
            ruleCountsByIdentifier: [:],
            identifiersApproachingLimit: []
        )

        do {
            try ContentBlockerService.clearAdvancedRuntime(groupIdentifier: GroupIdentifier.shared.value)
            statusDescription = LocalizedStrings.text("Ready.", comment: "Filter manager idle status")
        } catch {
            await ConcurrentLogManager.shared.error(
                .filterApply,
                "Failed to clear filter engine during onboarding reset",
                metadata: ["error": error.localizedDescription]
            )
            hasError = true
            statusDescription = LocalizedStrings.text("Failed", comment: "Generic failure status")
        }
        isLoading = false
    }

    func setupAsync() async {
        await dataManager.waitUntilLoaded()
        setup()
    }

    func setup() {
        filterUpdater.filterListManager = self

        // Load filter lists from protobuf data manager
        var storedFilterLists = dataManager.getFilterLists()

        // Migrate old AdGuard Annoyances filter to new split filters
        storedFilterLists = migrateOldAnnoyancesFilter(in: storedFilterLists)

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
                markNonSelectionChangesPending()
            }
        }

        var migratedFilterLists = loader.migrateFilterURLs(in: storedFilterLists)
        let defaultLists = loader.getDefaultFilterLists()
        let appliedUBlockDefaultMigration = migrateLegacyDefaultFiltersToUBlockCatalogIfNeeded(
            filters: &migratedFilterLists,
            defaultLists: defaultLists
        )
        var addedDefaultFilters = false
        let originalURLsByID = Dictionary(
            storedFilterLists.map { ($0.id, $0.url) },
            uniquingKeysWith: { first, _ in first }
        )

        // Merge any new default filters added in app updates
        if !migratedFilterLists.isEmpty {
            let existingURLs = Set(migratedFilterLists.map { $0.url })

            for defaultFilter in defaultLists {
                if !existingURLs.contains(defaultFilter.url) {
                    // New filter from app update - add unselected
                    var newFilter = defaultFilter
                    newFilter.isSelected = false
                    migratedFilterLists.append(newFilter)
                    addedDefaultFilters = true
                }
            }
        }

        migratedFilterLists = hydrateBuiltInFilterMetadata(in: migratedFilterLists, defaultLists: defaultLists)
        let appliedNativeDefaults = appliedUBlockDefaultMigration
            ? false
            : applyNativeCompilerDefaultsIfNeeded(
                to: &migratedFilterLists,
                defaultLists: defaultLists
            )

        filterLists = migratedFilterLists
        markCurrentStateApplied()

        // Ensure filter files use stable filenames and migrate legacy name-only files.
        Task.detached(priority: .utility) { [loader, migratedFilterLists] in
            for filter in migratedFilterLists {
                loader.migrateFilterFileIfNeeded(filter)
            }
        }

        // Persist URL migrations and newly added defaults. Catalog metadata is hydrated in memory
        // because older app data does not store languages/trust levels.
        let hasURLMigrations = migratedFilterLists.contains { filter in
            guard let originalURL = originalURLsByID[filter.id] else { return false }
            return originalURL != filter.url
        }
        if hasURLMigrations || addedDefaultFilters || appliedNativeDefaults || appliedUBlockDefaultMigration {
            Task { await self.saveFilterLists() }
        }

        // Only load defaults if truly no data exists
        if filterLists.isEmpty && !dataManager.isLoading {
            let defaultLists = loader.getDefaultFilterLists()
            filterLists = defaultLists
            saveFilterListsCoalesced()
        }

        // Load saved rule counts from protobuf data
        loadSavedRuleCounts()

        if appliedUBlockDefaultMigration || shouldResumeUBlockMigrationApply() {
            Task { @MainActor in
                await self.performUBlockMigrationApplyIfNeeded(reason: appliedUBlockDefaultMigration ? "catalogMigrated" : "resume")
            }
        }

        // Set up observer for disabled sites changes
        setupDisabledSitesObserver()

        markCurrentStateApplied()
        statusDescription = LocalizedStrings.format(
            "Initialized with %d filter list(s).",
            comment: "Filter manager initialization status",
            filterLists.count
        )
        // Update versions and counts in background without applying changes
        Task { await updateVersionsAndCounts() }
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

    private func migrateLegacyDefaultFiltersToUBlockCatalogIfNeeded(
        filters: inout [FilterList],
        defaultLists: [FilterList]
    ) -> Bool {
        guard FilterListLoader.isNativeCompilerEnabled else { return false }
        guard dataManager.uBlockDefaultCatalogMigrationVersion < UBlockMigrationKeys.targetVersion else { return false }

        let legacyDefaultNames: Set<String> = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "AdGuard Cookie Notices",
            "AdGuard Popups",
            "AdGuard Mobile App Banners",
            "AdGuard Other Annoyances",
            "AdGuard Widgets",
            "AdGuard Social Media Filter",
            "Fanboy's Annoyances Filter",
            "Fanboy's Social Blocking List",
            "Fanboy's Anti-AI Suggestions",
            "Online Security Filter",
            "Peter Lowe's Blocklist",
            "Anti-Adblock List",
            "AdGuard Experimental Filter",
            "EasyPrivacy",
            "d3Host List by d3ward",
            "Hagezi Pro Mini",
            "AdGuard Mobile Filter",
        ]
        let legacyDefaultURLFragments = [
            "FiltersRegistry/master/platforms/extension/safari/filters/",
            "FiltersRegistry/master/filters/",
            "filters.adtidy.org/ios/filters/",
        ]
        let legacyDefaults = filters.filter { filter in
            !filter.isCustom
                && (legacyDefaultNames.contains(filter.name)
                    || legacyDefaultURLFragments.contains { filter.url.absoluteString.contains($0) })
        }
        guard !legacyDefaults.isEmpty else { return false }

        let selectedLegacyNames = Set(legacyDefaults.filter(\.isSelected).map(\.name))
        let selectedNativeNames = nativeDefaultNamesMapped(from: selectedLegacyNames)
        let defaultsByName = Dictionary(defaultLists.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var migratedDefaults: [FilterList] = []
        for defaultFilter in defaultLists where !defaultFilter.isCustom {
            var filter = defaultFilter
            filter.isSelected = selectedNativeNames.contains(filter.name)
            migratedDefaults.append(filter)
        }

        filters.removeAll { filter in
            !filter.isCustom
                && (legacyDefaultNames.contains(filter.name)
                    || legacyDefaultURLFragments.contains { filter.url.absoluteString.contains($0) }
                    || defaultsByName[filter.name] != nil)
        }
        filters.insert(contentsOf: migratedDefaults, at: 0)
        dataManager.setUBlockDefaultCatalogMigrationInMemory(
            version: UBlockMigrationKeys.targetVersion,
            state: UBlockMigrationState.catalogMigrated.rawValue
        )
        invalidateAllTargetConversionCaches()
        logUBlockMigrationSummary(
            legacyDefaults: legacyDefaults,
            selectedLegacyNames: selectedLegacyNames,
            selectedNativeNames: selectedNativeNames,
            customFilterCount: filters.filter(\.isCustom).count
        )
        return true
    }

    private func shouldResumeUBlockMigrationApply() -> Bool {
        switch currentUBlockMigrationState() {
        case .catalogMigrated, .applyStarted, .applyFailed:
            return true
        case .notStarted, .applySucceeded:
            return false
        }
    }

    private func currentUBlockMigrationState() -> UBlockMigrationState {
        let raw = dataManager.uBlockDefaultCatalogMigrationState
        guard let state = UBlockMigrationState(rawValue: raw) else {
            return .notStarted
        }
        return state
    }

    private func setUBlockMigrationState(_ state: UBlockMigrationState) {
        dataManager.setUBlockDefaultCatalogMigrationInMemory(state: state.rawValue)
        Task { await dataManager.updateUBlockDefaultCatalogMigration(state: state.rawValue) }
    }

    private func invalidateAllTargetConversionCaches() {
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        let groupIdentifier = GroupIdentifier.shared.value
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            return
        }

        for target in targets {
            let baseFilename = ContentBlockerIncrementalCache.baseRulesFilename(for: target.rulesFilename)
            let advancedFilename = ContentBlockerIncrementalCache.baseAdvancedRulesFilename(for: target.rulesFilename)
            let filenames = [
                baseFilename,
                "\(baseFilename).count",
                "\(baseFilename).sha256",
                advancedFilename,
                target.rulesFilename,
            ]
            for filename in filenames {
                try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(filename))
            }
            ContentBlockerIncrementalCache.invalidateInputSignature(
                targetRulesFilename: target.rulesFilename,
                groupIdentifier: groupIdentifier
            )
        }
    }

    private func logUBlockMigrationSummary(
        legacyDefaults: [FilterList],
        selectedLegacyNames: Set<String>,
        selectedNativeNames: Set<String>,
        customFilterCount: Int
    ) {
        Task {
            await ConcurrentLogManager.shared.info(
                .filterApply,
                "Migrated legacy default filters to uBlock catalog",
                metadata: [
                    "legacyDefaultCount": "\(legacyDefaults.count)",
                    "selectedLegacy": selectedLegacyNames.sorted().joined(separator: ","),
                    "selectedNative": selectedNativeNames.sorted().joined(separator: ","),
                    "customFilterCount": "\(customFilterCount)",
                ]
            )
        }
    }

    private func performUBlockMigrationApplyIfNeeded(reason: String) async {
        guard shouldResumeUBlockMigrationApply() else { return }
        setUBlockMigrationState(.applyStarted)
        invalidateAllTargetConversionCaches()
        await ConcurrentLogManager.shared.info(
            .filterApply,
            "Applying migrated uBlock filter catalog automatically",
            metadata: [
                "reason": reason,
                "selectedFilters": "\(filterLists.filter(\.isSelected).count)",
            ]
        )
        await applyChanges()
        if hasError {
            setUBlockMigrationState(.applyFailed)
            markNonSelectionChangesPending()
            await ConcurrentLogManager.shared.error(
                .filterApply,
                "Automatic uBlock migration apply failed; will retry on next launch",
                metadata: ["status": statusDescription]
            )
        } else {
            setUBlockMigrationState(.applySucceeded)
            await dataManager.updateUBlockDefaultCatalogMigration(
                version: UBlockMigrationKeys.targetVersion,
                state: UBlockMigrationState.applySucceeded.rawValue
            )
            await ConcurrentLogManager.shared.info(
                .filterApply,
                "Automatic uBlock migration apply succeeded",
                metadata: ["selectedFilters": "\(filterLists.filter(\.isSelected).count)"]
            )
        }
    }

    private func nativeDefaultNamesMapped(from legacyNames: Set<String>) -> Set<String> {
        var names: Set<String> = []
        func add(_ values: String...) { values.forEach { names.insert($0) } }

        if legacyNames.contains("AdGuard Base Filter") || legacyNames.contains("Anti-Adblock List") {
            add("uBlock filters – Ads", "uBlock filters – Unbreak", "uBlock filters – Quick fixes", "EasyList")
        }
        if legacyNames.contains("AdGuard Tracking Protection Filter") || legacyNames.contains("EasyPrivacy") {
            add("uBlock filters – Privacy", "EasyPrivacy", "AdGuard/uBO – URL Tracking Protection")
        }
        if legacyNames.contains("Online Security Filter") {
            add("uBlock filters – Badware risks", "Online Malicious URL Blocklist")
        }
        if legacyNames.contains("Peter Lowe's Blocklist") {
            add("Peter Lowe’s Ad and tracking server list")
        }
        if legacyNames.contains("AdGuard Cookie Notices") {
            add("uBlock filters – Cookie Notices", "EasyList – Cookie Notices", "AdGuard – Cookie Notices")
        }
        if legacyNames.contains("AdGuard Popups") {
            add("AdGuard – Popup Overlays")
        }
        if legacyNames.contains("AdGuard Mobile App Banners") {
            add("AdGuard – Mobile App Banners")
        }
        if legacyNames.contains("AdGuard Other Annoyances") || legacyNames.contains("Fanboy's Annoyances Filter") {
            add("uBlock filters – Annoyances", "EasyList – Other Annoyances", "AdGuard – Other Annoyances")
        }
        if legacyNames.contains("AdGuard Widgets") {
            add("AdGuard – Widgets")
        }
        if legacyNames.contains("AdGuard Social Media Filter") || legacyNames.contains("Fanboy's Social Blocking List") {
            add("EasyList – Social Widgets", "AdGuard – Social Widgets")
        }
        if legacyNames.contains("Fanboy's Anti-AI Suggestions") {
            add("EasyList – AI Widgets")
        }
        if legacyNames.contains("AdGuard Experimental Filter") {
            add("uBlock filters – Experimental")
        }
        if legacyNames.contains("AdGuard Mobile Filter") {
            #if os(iOS)
                add("AdGuard – Mobile Ads")
            #endif
        }

        if names.isEmpty && !legacyNames.isEmpty {
            names = FilterListLoader.recommendedFilterNames
        }
        return names
    }

    private func applyNativeCompilerDefaultsIfNeeded(
        to filters: inout [FilterList],
        defaultLists: [FilterList]
    ) -> Bool {
        guard FilterListLoader.isNativeCompilerEnabled else { return false }
        let defaultsVersion = 1
        guard dataManager.nativeDefaultFiltersAppliedVersion < defaultsVersion else { return false }

        let recommendedURLs = Set(
            defaultLists
                .filter { FilterListLoader.recommendedFilterNames.contains($0.name) }
                .map(\.url)
        )
        let legacyCoreNames: Set<String> = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "EasyPrivacy",
            "Online Security Filter",
            "Peter Lowe's Blocklist",
            "d3Host List by d3ward",
            "AdGuard Cookie Notices",
            "AdGuard Popups",
            "AdGuard Mobile App Banners",
            "AdGuard Other Annoyances",
            "AdGuard Widgets",
            "Anti-Adblock List",
            "AdGuard Mobile Filter",
            "Hagezi Pro Mini",
        ]
        for index in filters.indices where !filters[index].isCustom {
            if recommendedURLs.contains(filters[index].url) {
                filters[index].isSelected = true
            } else if legacyCoreNames.contains(filters[index].name) {
                filters[index].isSelected = false
            }
        }

        dataManager.setNativeDefaultFiltersAppliedVersionInMemory(defaultsVersion)
        Task { await dataManager.updateNativeDefaultFiltersAppliedVersion(defaultsVersion) }
        return true
    }

    private func hydrateBuiltInFilterMetadata(in filters: [FilterList], defaultLists: [FilterList]) -> [FilterList] {
        let defaultsByURL = Dictionary(
            defaultLists.map { ($0.url, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return filters.map { filter in
            guard !filter.isCustom, let catalogFilter = defaultsByURL[filter.url] else {
                return filter
            }

            var hydrated = filter
            hydrated.name = catalogFilter.name
            hydrated.category = catalogFilter.category
            hydrated.description = catalogFilter.description
            hydrated.languages = catalogFilter.languages
            hydrated.trustLevel = catalogFilter.trustLevel
            return hydrated
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
        if let index = filterListIndexByID[id] {
            filterLists[index].isSelected.toggle()

            if filterLists[index].isSelected {
                filterLists[index].limitExceededReason = nil
                autoDisabledFilters.removeAll { $0.id == id }
            }

            saveFilterListsCoalesced()
            refreshPendingChanges()
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

        for index in filterLists.indices {
            if FilterListLoader.recommendedFilterNames.contains(filterLists[index].name) {
                filterLists[index].isSelected = true
            }
        }

        saveFilterListsCoalesced()
        refreshPendingChanges()
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
            let currentRulesLine: String
            if totalRules >= totalWarningThreshold {
                currentRulesLine = LocalizedStrings.format(
                    "Current Safari rules: %@ (near limit)",
                    comment: "Rule limit warning current rules line when near limit",
                    totalRules.formatted()
                )
            } else {
                currentRulesLine = LocalizedStrings.format(
                    "Current Safari rules: %@",
                    comment: "Rule limit warning current rules line",
                    totalRules.formatted()
                )
            }

            message = LocalizedStrings.format(
                "Safari limits each content blocker extension to %@ rules.\nTotal capacity (all wBlock blockers): %@ rules.\n\n%@\n\nwBlock distributes your enabled filter lists across multiple blockers to maximize capacity, but you may still hit Safari's limits if you enable too many large lists.",
                comment: "Rule limit warning body",
                ruleLimitPerBlocker.formatted(),
                totalCapacity.formatted(),
                currentRulesLine
            )
        }

        let perBlockerWarningThreshold = Int(Double(ruleLimitPerBlocker) * 0.8)
        let nearLimitBlockers = platformTargets
            .map { target -> (name: String, count: Int) in
                (target.displayName, ruleCountsByExtension[target.bundleIdentifier] ?? 0)
            }
            .filter { $0.count >= perBlockerWarningThreshold }
            .sorted { $0.count > $1.count }

        if !nearLimitBlockers.isEmpty {
            message += "\n\n"
            message += LocalizedStrings.text(
                "Blockers near the per-extension limit:",
                comment: "Rule limit warning section header"
            )
            message += "\n"
            message += nearLimitBlockers
                .map {
                    LocalizedStrings.format(
                        "%@: %@",
                        comment: "Rule limit warning blocker row",
                        $0.name,
                        $0.count.formatted()
                    )
                }
                .joined(separator: "\n")
        }

        let isNearLimit = totalRules >= totalWarningThreshold || !nearLimitBlockers.isEmpty
        ruleLimitWarningTitle = isNearLimit
            ? LocalizedStrings.text("Rule Limit Warning", comment: "Rule limit warning title")
            : LocalizedStrings.text("Rule Capacity", comment: "Rule capacity title")
        ruleLimitWarningMessage = message
        showingRuleLimitWarningAlert = true
    }
}
