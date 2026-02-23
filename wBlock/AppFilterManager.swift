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
    var missingFilters: [FilterList] = []
    var missingUserScripts: [UserScript] = []
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

    var customFilterLists: [FilterList] = []

    var filterListIndexByID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: filterLists.enumerated().map { ($1.id, $0) })
    }

    // Save filter lists
    func saveFilterLists() async {
        // Use existing updateFilterLists method from ProtobufDataManager+Extensions
        await dataManager.updateFilterLists(filterLists)
    }

    var pendingSaveTask: Task<Void, Never>?

    func saveFilterListsCoalesced() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            await saveFilterLists()
        }
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
        saveFilterListsCoalesced()

        await dataManager.updateRuleCounts(
            lastRuleCount: 0,
            ruleCountsByIdentifier: [:],
            identifiersApproachingLimit: []
        )

        ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)

        statusDescription = "Ready."
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
            saveFilterListsCoalesced()
        }

        // Load saved rule counts from protobuf data
        loadSavedRuleCounts()

        // Set up observer for disabled sites changes
        setupDisabledSitesObserver()

        statusDescription = "Initialized with \(filterLists.count) filter list(s)."
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

        saveFilterListsCoalesced()
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
}
