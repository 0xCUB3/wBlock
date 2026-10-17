//
//  AppFilterManager.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI
import CoreFoundation
import wBlockCoreService

private extension Notification.Name {
    static let wBlockResumeRequest = Notification.Name("wBlockResumeRequest")
    static let wBlockFilterUpdateRequest = Notification.Name("wBlockFilterUpdateRequest")
}

struct ApplyRunSnapshot {
    let filters: [FilterList]
    let configurations: [ApplyFilterConfiguration]
    let selectedFilterIDs: Set<UUID>
    let customFilterKeys: Set<String>
    let disabledSites: [String]
    let activeZapperRules: [String: [String]]
    let disabledZapperDomains: Set<String>
    let cosmeticSites: CosmeticFilteringPreference.Sites
}

@MainActor
class AppFilterManager: ObservableObject {
    private static let lastAppliedUpgradeSignatureKey = "wBlock.lastAppliedUpgradeSignature"
    private static let lastFailedUpgradeSignatureKey = "wBlock.lastFailedUpgradeSignature"
    @Published var filterLists: [FilterList] = []
    @Published var isLoading: Bool = false
    @Published var statusDescription: String = LocalizedStrings.text("Ready.", comment: "Filter manager idle status")
    @Published var lastConversionTime: String = LocalizedStrings.text("N/A", comment: "Unavailable metric placeholder")
    @Published var lastReloadTime: String = LocalizedStrings.text("N/A", comment: "Unavailable metric placeholder")
    @Published var lastRuleCount: Int = 0 {
        didSet { if lastRuleCount != oldValue { refreshAppliedRuleCounts() } }
    }
    @Published var hasError: Bool = false
    /// Content blockers that did not reload on the last apply (#648). Cleared on
    /// the next apply and once a targeted retry succeeds.
    @Published var failedReloadTargets: [ContentBlockerTargetInfo] = []
    @Published var progress: Float = 0
    @Published var updateCheckProgress: FilterListUpdater.FilterRefreshProgress?
    /// Advances whenever downloaded filter content is successfully written.
    @Published private(set) var downloadedFilterRevision = 0
    var missingFilters: [FilterList] = []
    var missingUserScripts: [UserScript] = []
    @Published var availableUpdates: [FilterList] = []
    @Published var availableScriptUpdates: [UserScript] = []
    @Published var showingNoUpdatesAlert = false
    @Published var hasUnappliedChanges = false
    @Published var showingApplyProgressSheet = false
    @Published var suppressBlockingOverlay = false
    @Published var isBlockingPaused: Bool = false
    @Published var pausedComponents: BlockingPauseComponents = []
    @Published var autoDisabledFilters: [FilterList] = []  // Filters auto-disabled due to rule limits
    @Published var showingAutoDisabledAlert = false

    // Per-extension rule count tracking (extension bundle ID -> Safari rule count)
    // This is the source of truth since extensions can serve multiple categories
    @Published var ruleCountsByExtension: [String: Int] = [:]
    /// Rule type breakdown for the capacity sheet. Kept here because SwiftUI rebuilds
    /// the sheet on every app switch, and view state would reset and make it flicker.
    @Published var appliedRuleCounts: AppliedRuleCounts?
    @Published var extensionsApproachingLimit: Set<String> = []

    // Performance tracking
    @Published var lastFastUpdateTime: String = LocalizedStrings.text("N/A", comment: "Unavailable metric placeholder")
    @Published var fastUpdateCount: Int = 0

    // New ViewModel-based progress tracking
    @Published var applyProgressViewModel = ApplyChangesViewModel()
    private var validatorClearIDs: [String] = []

    /// Ensures only one apply/update pipeline runs at a time across entry points.
    var isApplyInFlight = false
    /// An auto-update run in this process (launch or foreground catch-up). It
    /// applies on its own, so the toolbar spins and the sheet mirrors its stages.
    @Published private(set) var isAutoUpdateRunning = false
    /// False when the run started while the sheet showed something else.
    private var autoUpdateOwnsProgressSheet = false
    var exclusiveApplyTask: Task<Void, Never>?
    /// Set only after the current apply has reached a successful terminal state.
    var lastApplySucceeded = false

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
    private var resumeRequestObserver: NSObjectProtocol?
    private var filterUpdateRequestObserver: NSObjectProtocol?
    private var resumeApplyInFlight = false
    private var filterUpdateInFlight = false

    deinit {
        setupTask?.cancel()
        if let resumeRequestObserver {
            NotificationCenter.default.removeObserver(resumeRequestObserver)
        }
        if let filterUpdateRequestObserver {
            NotificationCenter.default.removeObserver(filterUpdateRequestObserver)
        }
    }

    // Per-site disable tracking
    var lastKnownDisabledSites: [String] = []
    let disabledSitesDirectoryMonitor = ProtobufDataDirectoryMonitor(queue: DispatchQueue(label: "skula.wBlock.disabled-sites-monitor", qos: .utility))
    var customFilterLists: [FilterList] {
        filterLists.filter(\.isCustom)
    }

    var appliedSelectedFilterIDs: Set<UUID> = []
    /// Monotonic local selection revision used to protect local choices during remote/async work.
    private(set) var selectionMutationRevision: UInt64 = 0
    private var appliedCustomFilterKeys: Set<String> = []
    private var appliedFilterConfigurations: [ApplyFilterConfiguration] = []
    var activeApplySnapshot: ApplyRunSnapshot?
    private var hasPendingSelectionChanges = false
    private var hasPendingNonSelectionChanges = false
    /// Pending work the filter list itself can't show, such as site or Zapper
    /// edits. Kept apart so a list edit that's undone clears only its own part.
    private var hasPendingExternalChanges = false

    var selectedFilterIDs: Set<UUID> {
        Set(filterLists.filter(\.isSelected).map(\.id))
    }

    var customFilterKeys: Set<String> {
        Set(filterLists.filter(\.isCustom).map(\.url.absoluteString))
    }

    var filterConfigurations: [ApplyFilterConfiguration] {
        filterLists.map(ApplyFilterConfiguration.init)
    }

    /// Single-ID lookup helper. Callers only ever look up one ID at a time, so a
    /// linear scan is cheaper than materializing a dictionary of every filter.
    func filterListIndex(for id: UUID) -> Int? {
        filterLists.firstIndex { $0.id == id }
    }

    func refreshPendingSelectionChanges() {
        hasPendingSelectionChanges = selectedFilterIDs != appliedSelectedFilterIDs
        refreshHasUnappliedChanges()
    }

    func refreshPendingChanges() {
        hasPendingSelectionChanges = selectedFilterIDs != appliedSelectedFilterIDs
        hasPendingNonSelectionChanges = hasPendingExternalChanges
            || filterConfigurations != appliedFilterConfigurations
            || customFilterKeys != appliedCustomFilterKeys
        refreshHasUnappliedChanges()
    }

    /// A custom list whose first download failed has nothing to apply, so it
    /// joins the applied baseline as-is instead of lighting up Apply.
    func acknowledgeUndownloadedFilter(_ id: UUID) {
        if let filter = filterLists.first(where: { $0.id == id }) {
            appliedCustomFilterKeys.insert(filter.url.absoluteString)
            appliedFilterConfigurations = ApplyFilterConfiguration.acknowledging(
                id, in: filterConfigurations, baseline: appliedFilterConfigurations)
            if filter.isSelected { appliedSelectedFilterIDs.insert(id) }
        }
        refreshPendingChanges()
    }

    func markNonSelectionChangesPending() {
        hasPendingExternalChanges = true
        hasPendingNonSelectionChanges = true
        refreshHasUnappliedChanges()
    }

    var autoApplyTask: Task<Void, Never>?

    func markCurrentStateApplied() {
        appliedSelectedFilterIDs = selectedFilterIDs
        appliedCustomFilterKeys = customFilterKeys
        appliedFilterConfigurations = filterConfigurations
        hasPendingSelectionChanges = false
        hasPendingNonSelectionChanges = false
        hasPendingExternalChanges = false
        hasUnappliedChanges = false
        autoApplyTask?.cancel()
        autoApplyTask = nil
    }

    private func currentUpgradeSignature() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return "\(appVersion)|\(ContentBlockerService.embeddedCompatibilityRulesVersion)"
    }

    private func storedUpgradeSignature() -> String? {
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
        return defaults.string(forKey: Self.lastAppliedUpgradeSignatureKey)
    }

    func persistUpgradeRebuildSignature() {
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
        defaults.set(currentUpgradeSignature(), forKey: Self.lastAppliedUpgradeSignatureKey)
    }

    func persistFailedUpgradeRebuildSignature() {
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
        defaults.set(currentUpgradeSignature(), forKey: Self.lastFailedUpgradeSignatureKey)
    }

    func clearFailedUpgradeRebuildSignature() {
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
        defaults.removeObject(forKey: Self.lastFailedUpgradeSignatureKey)
    }

    private func storedFailedUpgradeSignature() -> String? {
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
        return defaults.string(forKey: Self.lastFailedUpgradeSignatureKey)
    }

    func captureApplySnapshot() {
        activeApplySnapshot = ApplyRunSnapshot(
            filters: filterLists,
            configurations: filterConfigurations,
            selectedFilterIDs: selectedFilterIDs,
            customFilterKeys: customFilterKeys,
            disabledSites: effectiveFilterDisabledSites(),
            activeZapperRules: dataManager.getActiveZapperRulesByHost(),
            disabledZapperDomains: Set(dataManager.getDisabledZapperDomains()),
            cosmeticSites: CosmeticFilteringPreference.effectiveSites()
        )
    }

    func commitApplySnapshot(_ snapshot: ApplyRunSnapshot) {
        appliedSelectedFilterIDs = snapshot.selectedFilterIDs
        appliedCustomFilterKeys = snapshot.customFilterKeys
        appliedFilterConfigurations = snapshot.configurations
        hasPendingSelectionChanges = selectedFilterIDs != snapshot.selectedFilterIDs
        hasPendingExternalChanges = effectiveFilterDisabledSites() != snapshot.disabledSites
            || dataManager.getActiveZapperRulesByHost() != snapshot.activeZapperRules
            || Set(dataManager.getDisabledZapperDomains()) != snapshot.disabledZapperDomains
            || CosmeticFilteringPreference.effectiveSites() != snapshot.cosmeticSites
        hasPendingNonSelectionChanges = hasPendingExternalChanges || filterConfigurations != snapshot.configurations
        refreshHasUnappliedChanges()
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

    func scheduleAutoApplyDebounce() {
        autoApplyTask?.cancel()
        autoApplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self,
                  self.hasUnappliedChanges,
                  !self.isLoading,
                  !self.isApplyInFlight,
                  !self.pausedComponents.contains(.filters)
            else { return }
            // Applying pending edits must not double as an update check; only explicit
            // updates and the auto-update scheduler refresh lists already on disk.
            await self.performFilterUpdate(checkForUpdates: false, downloadMissing: true)
        }
    }

    // Save filter lists
    @discardableResult
    func saveFilterLists() async -> Bool {
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

        self.pausedComponents = BlockingPauseStore.pausedComponents()
        self.isBlockingPaused = !self.pausedComponents.isEmpty
        registerResumeRequestObserver()
        registerFilterUpdateRequestObserver()

        // Wait for ProtobufDataManager to finish loading before setting up.
        setupTask = Task { @MainActor [weak self] in
            await self?.setupAsync()
        }
    }

    private static let resumeRequestRelay: Void = {
        let notificationName = BlockingPauseStore.resumeRequestNotificationName as CFString
        // Darwin notifications do not retain their observer pointer. Keep this relay
        // process-global and forward locally; individual managers own removable
        // NotificationCenter tokens instead of registering an unowned self pointer.
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            AppFilterManager.resumeRequestCallback,
            notificationName,
            nil,
            .deliverImmediately
        )
    }()

    private func registerResumeRequestObserver() {
        _ = Self.resumeRequestRelay
        resumeRequestObserver = NotificationCenter.default.addObserver(
            forName: .wBlockResumeRequest,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard BlockingPauseStore.consumeResumeRequest() else { return }
                await self.handleResumeRequest()
            }
        }

        if BlockingPauseStore.consumeResumeRequest() {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.handleResumeRequest()
            }
        }
    }

    private func handleResumeRequest() async {
        guard !resumeApplyInFlight else { return }
        resumeApplyInFlight = true
        defer { resumeApplyInFlight = false }

        // The manager is created before launch migration and filter-list loading finish.
        // Waiting here prevents a Safari request from applying an empty startup snapshot.
        await waitUntilReady()
        guard BlockingPauseStore.isPaused() else {
            BlockingPauseStore.setResumeSucceeded()
            return
        }

        BlockingPauseStore.setResumeApplying()
        let succeeded = await setBlockingPaused(false)
        if succeeded {
            BlockingPauseStore.setResumeSucceeded()
        } else {
            BlockingPauseStore.setResumeFailed(
                statusDescription.isEmpty ? "Failed to resume blocking." : statusDescription
            )
        }
    }

    private static let resumeRequestCallback: CFNotificationCallback = { _, _, _, _, _ in
        NotificationCenter.default.post(name: .wBlockResumeRequest, object: nil)
    }

    private static let filterUpdateRequestRelay: Void = {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            AppFilterManager.filterUpdateRequestCallback,
            FilterUpdatePopupStatus.requestNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }()

    private func registerFilterUpdateRequestObserver() {
        #if os(macOS)
        // In a headless launch the AppDelegate consumes the request itself.
        if HeadlessLaunch.isHeadlessProcess { return }
        #endif
        _ = Self.filterUpdateRequestRelay
        filterUpdateRequestObserver = NotificationCenter.default.addObserver(
            forName: .wBlockFilterUpdateRequest,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let claim = FilterUpdatePopupStatus.consumeUpdateRequest() else { return }
                await self.handleFilterUpdateRequest(claim: claim)
            }
        }

        if let claim = FilterUpdatePopupStatus.consumeUpdateRequest() {
            Task { @MainActor [weak self] in
                await self?.handleFilterUpdateRequest(claim: claim)
            }
        }
    }

    private func handleFilterUpdateRequest(claim: FilterUpdatePopupStatus.ClaimToken) async {
        guard !filterUpdateInFlight else { return }
        filterUpdateInFlight = true
        defer { filterUpdateInFlight = false }

        await waitUntilReady()
        let outcome = await SharedAutoUpdateManager.shared.maybeRunAutoUpdate(
            trigger: "Popup",
            force: true
        )
        FilterUpdatePopupStatus.finish(outcome, claim: claim)
    }

    private static let filterUpdateRequestCallback: CFNotificationCallback = { _, _, _, _, _ in
        NotificationCenter.default.post(name: .wBlockFilterUpdateRequest, object: nil)
    }

    /// Performs the complete reset used by every Restart Onboarding entry point.
    @MainActor
    func completeResetForOnboarding() async {
        resetOnboardingUserDefaults()
        await dataManager.resetToDefaultData(preservingOnboardingCompletion: true)
        await resetForOnboarding()
        await UserScriptManager.shared.simulateFreshInstall()
        await SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()
        _ = await dataManager.setHasCompletedOnboarding(false)
    }

    private func resetOnboardingUserDefaults() {
        if let suiteDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) {
            suiteDefaults.removePersistentDomain(forName: GroupIdentifier.shared.value)
            suiteDefaults.synchronize()
        }
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        UserDefaults.standard.synchronize()
    }

    @MainActor
    func publishDownloadedFilter() {
        downloadedFilterRevision &+= 1
    }

    /// Resets the manager to its initial state so onboarding can run again.
    @MainActor
    func resetForOnboarding() async {
        // The reset ends by presenting onboarding from the same view that owns the
        // blocking progress sheet. Presenting that sheet here and then the onboarding
        // cover while the sheet is still dismissing leaves the cover half-presented
        // over the tab view on iOS, so keep the blocking overlay suppressed for the
        // whole reset.
        suppressBlockingOverlay = true
        defer { suppressBlockingOverlay = false }
        isLoading = true
        statusDescription = LocalizedStrings.text("Resetting…", comment: "Filter manager reset status")
        markCurrentStateApplied()
        showingApplyProgressSheet = false
        missingFilters = []
        availableUpdates = []
        availableScriptUpdates = []
        ruleCountsByExtension = [:]
        extensionsApproachingLimit = []
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

        var cacheCleanupError: Error?
        if let containerURL = loader.getSharedContainerURL() {
            do {
                try Self.removeDownloadedFilterCachesForOnboarding(
                    defaultLists: defaultLists,
                    containerURL: containerURL
                )
            } catch {
                cacheCleanupError = error
            }
        } else {
            cacheCleanupError = CocoaError(.fileNoSuchFile)
        }

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
            if cacheCleanupError == nil {
                statusDescription = LocalizedStrings.text("Ready.", comment: "Filter manager idle status")
            }
        } catch {
            await ConcurrentLogManager.shared.error(
                .filterApply,
                LocalizedStrings.text("Failed to clear filter engine during onboarding reset"),
                metadata: ["error": LogErrorDescriber.describe(error)]
            )
            hasError = true
            statusDescription = LocalizedStrings.text("Failed", comment: "Generic failure status")
        }
        if let cacheCleanupError {
            await ConcurrentLogManager.shared.error(
                .filterApply,
                "Failed to clear downloaded filter caches during onboarding reset",
                metadata: ["error": LogErrorDescriber.describe(cacheCleanupError)]
            )
            hasError = true
            statusDescription = LocalizedStrings.text("Failed", comment: "Generic failure status")
        }
        isLoading = false
    }

    nonisolated private static func removeDownloadedFilterCachesForOnboarding(
        defaultLists: [FilterList],
        containerURL: URL
    ) throws {
        let fileManager = FileManager.default
        var firstError: Error?

        for filter in defaultLists {
            do {
                try ContentBlockerIncrementalCache.removeFilterCacheFiles(
                    for: filter,
                    containerURL: containerURL,
                    fileManager: fileManager
                )
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        let orphanPrefixes = [
            "custom-", "diff-baseline-custom-", "filter-", "diff-baseline-filter-"
        ]
        let contents = try fileManager.contentsOfDirectory(
            at: containerURL,
            includingPropertiesForKeys: nil
        )
        for url in contents {
            let filename = url.lastPathComponent
            guard filename.hasSuffix(".txt"),
                  orphanPrefixes.contains(where: filename.hasPrefix)
            else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                if (error as NSError).code != NSFileNoSuchFileError && firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }

    func waitUntilReady() async {
        await setupTask?.value
    }

    private func setupAsync() async {
        await dataManager.waitUntilLoaded()
        setup()
        for uuid in validatorClearIDs {
            await dataManager.setFilterValidators(uuid, etag: nil, lastModified: nil)
        }
        validatorClearIDs.removeAll()
        setupTask = nil
    }

    func setup() {
        filterUpdater.filterListManager = self
        SharedAutoUpdateManager.runProgressHandler = { [weak self] in self?.showAutoUpdateProgress($0) }

        // Load filter lists from protobuf data manager. Keep the in-memory
        // boundary unique even when older or concurrent data supplies repeats.
        var storedFilterLists = deduplicateFilterIDs(dataManager.getFilterLists())
        var selectedDeprecatedListWasRemoved = false

        // Built-in lists wBlock no longer ships. A selected one becomes a custom
        // list so the user keeps it; an unselected one is dropped.
        let deprecatedFilterLists = storedFilterLists.filter(FilterListLoader.isRetiredBuiltIn)
        if !deprecatedFilterLists.isEmpty {
            storedFilterLists = storedFilterLists.compactMap { filter in
                guard FilterListLoader.isRetiredBuiltIn(filter) else { return filter }
                guard filter.isSelected else { return nil }
                var kept = filter
                kept.isCustom = true
                kept.hasUserProvidedName = true
                return kept
            }

            let removedFilterIDs = deprecatedFilterLists.filter { !$0.isSelected }.map(\.id)
            Task {
                for id in removedFilterIDs {
                    await self.dataManager.removeFilterList(withId: id)
                }
                await ConcurrentLogManager.shared.info(
                    .system, LocalizedStrings.text("Removed deprecated filter list(s)"),
                    metadata: ["filters": deprecatedFilterLists.map(\.name).joined(separator: ", ")]
                )
            }

            if deprecatedFilterLists.contains(where: \.isSelected) {
                selectedDeprecatedListWasRemoved = true
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
                    // New filter from app update - add unselected, except the
                    // hosts that used to be built in
                    var newFilter = defaultFilter
                    newFilter.isSelected = defaultFilter.url == FilterListLoader.adTrackingHostsURL
                        && migratedFilterLists.contains(where: \.isSelected)
                    migratedFilterLists.append(newFilter)
                    addedDefaultFilters = true
                }
            }
        }
        migratedFilterLists = FilterListSetup.hydrate(migratedFilterLists, defaults: defaultLists)
        migratedFilterLists = deduplicateFilterIDs(migratedFilterLists)
        validatorClearIDs = migratedFilterLists.compactMap { filter in
            guard let originalURL = originalURLsByID[filter.id], originalURL != filter.url else { return nil }
            return filter.id.uuidString
        }

        filterLists = migratedFilterLists
        markCurrentStateApplied()

        // Persist URL migrations and newly added defaults. Catalog metadata is hydrated in memory
        // because older app data does not store languages/trust levels.
        let hasURLMigrations = migratedFilterLists.contains { filter in
            guard let originalURL = originalURLsByID[filter.id] else { return false }
            return originalURL != filter.url
        }
        if hasURLMigrations || addedDefaultFilters || selectedDeprecatedListWasRemoved {
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

        let currentSignature = currentUpgradeSignature()
        let storedSignature = storedUpgradeSignature()
        let signatureMismatch = storedSignature != currentSignature
        let needsRebuild = dataManager.hasCompletedOnboarding
            && (hasURLMigrations || selectedDeprecatedListWasRemoved || signatureMismatch)
        if needsRebuild {
            markNonSelectionChangesPending()
            if storedFailedUpgradeSignature() == currentSignature {
                autoApplyTask?.cancel()
                autoApplyTask = nil
            }
        } else {
            markCurrentStateApplied()
        }
        statusDescription = LocalizedStrings.format(
            "Initialized with %d filter list(s).",
            comment: "Filter manager initialization status",
            filterLists.count
        )
        // Update versions and counts in background without applying changes
        Task { await updateVersionsAndCounts() }
    }


    func deduplicateFilterIDs(_ filters: [FilterList]) -> [FilterList] {
        var latestByID: [UUID: FilterList] = [:]
        var firstIDs: [UUID] = []
        var seenIDs = Set<UUID>()
        for filter in filters {
            latestByID[filter.id] = filter
            if seenIDs.insert(filter.id).inserted {
                firstIDs.append(filter.id)
            }
        }
        return firstIDs.compactMap { latestByID[$0] }
    }


    /// Puts built-in lists back in their catalog categories and moves custom lists to Other.
    func resetCategories() {
        let defaults = Dictionary(
            loader.getDefaultFilterLists().map { ($0.url, $0.category) },
            uniquingKeysWith: { first, _ in first }
        )
        for index in filterLists.indices {
            let filter = filterLists[index]
            filterLists[index].category = filter.isCustom ? .custom : defaults[filter.url] ?? filter.category
        }
        saveFilterListsCoalesced()
        // Compared with what was applied, so a reset that moves nothing asks for no apply (#953).
        refreshPendingChanges()
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

    /// `checkForUpdates: false` skips refreshing downloaded lists. Selected lists that have never
    /// been fetched are downloaded only when `downloadMissing` (default: `checkForUpdates`) is true.
    @discardableResult
    func performFilterUpdate(
        showProgress: Bool = true, checkForUpdates: Bool = true, downloadMissing: Bool? = nil
    ) async -> Bool {
        refreshMissingItems()

        let started = await performExclusiveApply {
            self.prepareApplyRunState()
            self.failedReloadTargets = []
            self.showingApplyProgressSheet = showProgress

            if downloadMissing ?? checkForUpdates, !self.missingFilters.isEmpty || !self.missingUserScripts.isEmpty {
                await self.downloadMissingItemsSilently()
            }

            await self.applyChanges(
                prepareState: false,
                skipPreApplyUpdates: !checkForUpdates
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

    static func requiresFullApply(
        hasUnappliedChanges: Bool,
        missingFilterCount: Int,
        missingScriptCount: Int
    ) -> Bool {
        hasUnappliedChanges || missingFilterCount > 0 || missingScriptCount > 0
    }

    func applyOrCheckForUpdates() {
        guard !isLoading, !isApplyInFlight, !isAutoUpdateRunning else { return }
        isLoading = true
        statusDescription = LocalizedStrings.text("Checking for updates...", comment: "Update check status")
        Task {
            await self.waitUntilReady()
            await UserScriptManager.shared.waitUntilReady()
            if self.filterUpdater.userScriptManager == nil {
                self.setUserScriptManager(UserScriptManager.shared)
            }
            self.refreshMissingItems()
            if Self.requiresFullApply(
                hasUnappliedChanges: self.hasUnappliedChanges,
                missingFilterCount: self.missingFilters.count,
                missingScriptCount: self.missingUserScripts.count
            ) {
                let started = await self.performFilterUpdate()
                if !started {
                    self.isLoading = false
                }
            } else {
                await self.checkForUpdates()
            }
        }
    }

    /// A background apply (iCloud sync, catch-up) only spins the toolbar
    /// button; tapping it opens the sheet a foreground apply shows.
    func showBackgroundApplyProgress() {
        guard isApplyInFlight || (isAutoUpdateRunning && autoUpdateOwnsProgressSheet) else { return }
        showingApplyProgressSheet = true
    }

    private func showAutoUpdateProgress(_ progress: SharedAutoUpdateManager.RunProgress) {
        let sheet = applyProgressViewModel
        if progress == .finished {
            guard isAutoUpdateRunning else { return }
            isAutoUpdateRunning = false
            if autoUpdateOwnsProgressSheet {
                sheet.updateIsLoading(false)
                showingApplyProgressSheet = false
            }
            return
        }
        if !isAutoUpdateRunning {
            isAutoUpdateRunning = true
            autoUpdateOwnsProgressSheet = !showingApplyProgressSheet
            if autoUpdateOwnsProgressSheet { sheet.beginProgressRun() }
        }
        guard autoUpdateOwnsProgressSheet else { return }
        switch progress {
        case .checking(let done, let total):
            sheet.updateFiltersChecked(done, total: total)
        case .converting(let done, let total):
            sheet.updatePhaseCompletion(scripts: true, reading: true)
            sheet.updateProcessedCount(done, total: total)
            sheet.updateConvertingDone(done)
        case .reloading(let done, _):
            sheet.updatePhaseCompletion(converting: true)
            sheet.updateReloadingDone(done)
        case .finished:
            break
        }
    }

    func forceApplyChanges(checkForUpdates: Bool = false) {
        guard !isLoading, !isApplyInFlight, !isAutoUpdateRunning else { return }
        clearFailedUpgradeRebuildSignature()
        isLoading = true
        showingNoUpdatesAlert = false
        statusDescription = checkForUpdates
            ? LocalizedStrings.text("Checking for updates...", comment: "Apply pipeline status")
            : LocalizedStrings.text("Applying filters...", comment: "Apply pipeline stage")
        applyProgressViewModel.beginProgressRun()
        showingApplyProgressSheet = true
        Task {
            await self.waitUntilReady()
            await UserScriptManager.shared.waitUntilReady()
            if self.filterUpdater.userScriptManager == nil {
                self.setUserScriptManager(UserScriptManager.shared)
            }
            let started = await self.performFilterUpdate(checkForUpdates: checkForUpdates)
            if !started {
                if !self.isApplyInFlight {
                    self.showingApplyProgressSheet = false
                    self.isLoading = false
                }
            }
        }
    }

    /// Sets a filter's selection state without depending on the caller's stale toggle state.
    @discardableResult
    func setFilterListSelection(id: UUID, selected: Bool) -> Bool {
        guard let index = filterListIndex(for: id), filterLists[index].isSelected != selected else {
            return false
        }

        selectionMutationRevision &+= 1
        filterLists[index].isSelected = selected
        if selected {
            filterLists[index].limitExceededReason = nil
            autoDisabledFilters.removeAll { $0.id == id }
        }

        saveFilterListsCoalesced()
        refreshPendingChanges()
        return true
    }

    func setFilterList(_ id: UUID, updatesAutomatically: Bool) {
        guard let index = filterListIndex(for: id),
              filterLists[index].updatesAutomatically != updatesAutomatically else { return }
        filterLists[index].updatesAutomatically = updatesAutomatically
        saveFilterListsCoalesced()
    }

    @discardableResult
    func setExcludedSites(_ sites: [String], for id: UUID) -> Bool {
        guard let index = filterListIndex(for: id) else { return false }
        let normalized = FilterListSiteExclusion.normalizedDomains(from: sites)
        guard filterLists[index].excludedSites != normalized else { return false }
        filterLists[index].excludedSites = normalized
        saveFilterListsCoalesced()
        refreshPendingChanges()
        return true
    }

    @discardableResult
    func setSelectedSites(_ sites: [String]?, for id: UUID) -> Bool {
        guard let index = filterListIndex(for: id) else { return false }
        let normalized = sites.map { FilterListSiteExclusion.normalizedDomains(from: $0) }
        guard filterLists[index].selectedSites != normalized else { return false }
        filterLists[index].selectedSites = normalized
        saveFilterListsCoalesced()
        refreshPendingChanges()
        return true
    }
}
