//
//  AppFilterManager.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI
import CoreFoundation
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
    @Published var showingNoUpdatesAlert = false
    @Published var hasUnappliedChanges = false
    @Published var showingApplyProgressSheet = false
    @Published var suppressBlockingOverlay = false
    @Published var isBlockingPaused: Bool = false
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

    /// Ensures only one apply/update pipeline runs at a time across entry points.
    var isApplyInFlight = false

    // Internal counters used for apply-run summary/progress math.
    var sourceRulesCount: Int = 0
    var processedFiltersCount: Int = 0
    @Published var currentPlatform: Platform

    // Dependencies
    let loader: FilterListLoader
    private(set) var filterUpdater: FilterListUpdater
    let logManager: ConcurrentLogManager
    let dataManager = ProtobufDataManager.shared
    private var setupTask: Task<Void, Never>?

    // Per-site disable tracking
    var lastKnownDisabledSites: [String] = []
    let disabledSitesDirectoryMonitor = ProtobufDataDirectoryMonitor(queue: DispatchQueue(label: "skula.wBlock.disabled-sites-monitor", qos: .utility))
    var customFilterLists: [FilterList] {
        filterLists.filter(\.isCustom)
    }

    var appliedSelectedFilterIDs: Set<UUID> = []
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

    private var autoApplyTask: Task<Void, Never>?

    func markCurrentStateApplied() {
        appliedSelectedFilterIDs = selectedFilterIDs
        appliedCustomFilterKeys = customFilterKeys
        hasPendingSelectionChanges = false
        hasPendingNonSelectionChanges = false
        hasUnappliedChanges = false
        autoApplyTask?.cancel()
        autoApplyTask = nil
    }

    private func refreshHasUnappliedChanges() {
        hasUnappliedChanges = hasPendingSelectionChanges || hasPendingNonSelectionChanges
        if hasUnappliedChanges {
            scheduleAutoApplyDebounce()
        } else {
            autoApplyTask?.cancel()
            autoApplyTask = nil
        }
    }

    private func scheduleAutoApplyDebounce() {
        autoApplyTask?.cancel()
        autoApplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self, self.hasUnappliedChanges, !self.isLoading, !self.isApplyInFlight, !self.isBlockingPaused else { return }
            self.checkAndEnableFilters(forceReload: true)
        }
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
        self.filterUpdater = FilterListUpdater(loader: self.loader)

        #if os(macOS)
            self.currentPlatform = .macOS
        #else
            self.currentPlatform = .iOS
        #endif

        self.isBlockingPaused = BlockingPauseStore.isPaused()
        registerResumeRequestObserver()

        // Wait for ProtobufDataManager to finish loading before setting up.
        setupTask = Task { @MainActor [weak self] in
            await self?.setupAsync()
        }
    }

    private func registerResumeRequestObserver() {
        let notificationName = BlockingPauseStore.resumeRequestNotificationName as CFString
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            Self.resumeRequestCallback,
            notificationName,
            nil,
            .deliverImmediately
        )

        if BlockingPauseStore.consumeResumeRequest() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.setBlockingPaused(false)
            }
        }
    }

    private static let resumeRequestCallback: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        let pointer = observer
        Task { @MainActor in
            guard BlockingPauseStore.consumeResumeRequest() else { return }
            let manager = Unmanaged<AppFilterManager>.fromOpaque(pointer).takeUnretainedValue()
            await manager.setBlockingPaused(false)
        }
    }

    /// Resets the manager to its initial state so onboarding can run again.
    @MainActor
    func resetForOnboarding() async {
        isLoading = true
        statusDescription = LocalizedStrings.text("Resetting…", comment: "Filter manager reset status")
        markCurrentStateApplied()
        showingApplyProgressSheet = false
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

        let groupIdentifier = GroupIdentifier.shared.value
        do {
            try await Task.detached {
                try ContentBlockerService.publishCombinedFilterEngine(
                    combinedAdvancedRules: "",
                    groupIdentifier: groupIdentifier
                )
            }.value
            statusDescription = LocalizedStrings.text("Ready.", comment: "Filter manager idle status")
        } catch {
            await ConcurrentLogManager.shared.error(
                .filterApply,
                LocalizedStrings.text("Failed to clear filter engine during onboarding reset"),
                metadata: ["error": error.localizedDescription]
            )
            hasError = true
            statusDescription = LocalizedStrings.text("Failed", comment: "Generic failure status")
        }
        isLoading = false
    }

    func waitUntilReady() async {
        await setupTask?.value
    }

    private func setupAsync() async {
        await dataManager.waitUntilLoaded()
        setup()
        setupTask = nil
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
                && (filter.name == "d3Host List by d3ward"
                    || filter.url.absoluteString.contains("d3ward/toolz"))
        }
        if !deprecatedFilterLists.isEmpty {
            let removedSelected = deprecatedFilterLists.contains(where: { $0.isSelected })
            storedFilterLists.removeAll { filter in
                !filter.isCustom
                    && (filter.name == "d3Host List by d3ward"
                        || filter.url.absoluteString.contains("d3ward/toolz"))
            }

            let deprecatedFilterIDs = deprecatedFilterLists.map(\.id)
            Task {
                for id in deprecatedFilterIDs {
                    await self.dataManager.removeFilterList(withId: id)
                }
                await ConcurrentLogManager.shared.info(
                    .system, LocalizedStrings.text("Removed deprecated filter list(s)"),
                    metadata: ["filters": deprecatedFilterLists.map(\.name).joined(separator: ", ")]
                )
            }

            if removedSelected {
                markNonSelectionChangesPending()
            }
        }

        var migratedFilterLists = loader.migrateFilterURLs(in: storedFilterLists)
        let defaultLists = loader.getDefaultFilterLists()
        for defaultFilter in defaultLists {
            loader.migrateBuiltInFilterFilesIfNeeded(defaultFilter)
        }
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

        filterLists = migratedFilterLists
        markCurrentStateApplied()

        // Ensure custom filter files use ID-based filenames so users can rename lists safely.
        Task.detached(priority: .utility) { [loader, migratedFilterLists] in
            for filter in migratedFilterLists where filter.isCustom {
                loader.migrateCustomFilterFileIfNeeded(filter)
            }
        }

        // Persist URL migrations and newly added defaults. Catalog metadata is hydrated in memory
        // because older app data does not store languages/trust levels.
        let hasURLMigrations = migratedFilterLists.contains { filter in
            guard let originalURL = originalURLsByID[filter.id] else { return false }
            return originalURL != filter.url
        }
        if hasURLMigrations || addedDefaultFilters {
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
    /// Runs the complete filter update/apply pipeline and waits for it to finish.
    ///
    /// The same method is used by the UI-triggered path and by the headless App Intent.
    /// A headless run suppresses progress-sheet state but still uses the normal download,
    /// conversion, persistence, and content-blocker reload pipeline.
    private func refreshMissingItems() {
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
    }

    @discardableResult
    func performFilterUpdate(showProgress: Bool = true) async -> Bool {
        refreshMissingItems()

        let started = await performExclusiveApply {
            self.prepareApplyRunState()
            self.showingApplyProgressSheet = showProgress

            if !self.missingFilters.isEmpty || !self.missingUserScripts.isEmpty {
                await self.downloadMissingItemsSilently()
            }

            await self.applyChanges(
                prepareState: false,
                skipPreApplyUpdates: false
            )
        }

        if !started {
            await ConcurrentLogManager.shared.warning(
                .filterApply,
                LocalizedStrings.text(
                    "Skipped overlapping apply request",
                    comment: "Apply pipeline concurrency guard"
                ),
                metadata: ["entry": "performFilterUpdate"]
            )
        }
        return started
    }

    func checkAndEnableFilters(forceReload: Bool = false) {
        refreshMissingItems()
        let hasMissingItems = !missingFilters.isEmpty || !missingUserScripts.isEmpty
        if hasMissingItems || forceReload || hasUnappliedChanges {
            Task {
                await self.performFilterUpdate()
            }
        }
    }

    func toggleFilterListSelection(id: UUID) {
        guard let index = filterListIndexByID[id] else { return }
        setFilterListSelection(id: id, selected: !filterLists[index].isSelected)
    }

    /// Sets a filter's selection state without depending on the caller's stale toggle state.
    @discardableResult
    func setFilterListSelection(id: UUID, selected: Bool) -> Bool {
        guard let index = filterListIndexByID[id], filterLists[index].isSelected != selected else {
            return false
        }

        filterLists[index].isSelected = selected
        if selected {
            filterLists[index].limitExceededReason = nil
            autoDisabledFilters.removeAll { $0.id == id }
        }

        saveFilterListsCoalesced()
        refreshPendingChanges()
        return true
    }

    // MARK: - Rule limit UX

    func showRuleLimitWarning() {
        let ruleLimitPerBlocker = 150_000
        let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        let totalCapacity = platformTargets.count * ruleLimitPerBlocker

        let totalRules = lastRuleCount
        guard totalRules >= totalCapacity else { return }

        var message = ""
        let currentRulesLine = LocalizedStrings.format(
            "Current Safari rules: %@",
            comment: "Rule limit warning current rules line",
            totalRules.formatted()
        )

        message = LocalizedStrings.format(
            "Safari limits each content blocker extension to %@ rules.\nTotal capacity (all wBlock blockers): %@ rules.\n\n%@\n\nwBlock distributes your enabled filter lists across multiple blockers to maximize capacity, but you may still hit Safari's limits if you enable too many large lists.",
            comment: "Rule limit warning body",
            ruleLimitPerBlocker.formatted(),
            totalCapacity.formatted(),
            currentRulesLine
        )

        message += "\n\n"
        message += LocalizedStrings.text(
            "More lists rarely means better blocking: most overlap with the recommended defaults and mainly use up rule capacity. Annoyances and regional filters are the main exceptions.",
            comment: "Rule limit warning footer note about extra lists"
        )

        let isAtTotalLimit = totalRules >= totalCapacity
        ruleLimitWarningTitle = isAtTotalLimit
            ? LocalizedStrings.text("Rule Limit Warning", comment: "Rule limit warning title")
            : LocalizedStrings.text("Rule Capacity", comment: "Rule capacity title")
        ruleLimitWarningMessage = message
        showingRuleLimitWarningAlert = true
    }
}
