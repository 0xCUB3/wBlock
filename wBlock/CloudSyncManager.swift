import CloudKit
import Combine
import CryptoKit
import Foundation
import os.log
import Security
import wBlockCoreService

private enum CloudSyncError: LocalizedError {
    case cloudKitUnavailable

    var errorDescription: String? {
        switch self {
        case .cloudKitUnavailable:
            return "iCloud is not available in this build"
        }
    }
}

@MainActor
final class CloudSyncManager: ObservableObject {
    enum SyncStatus {
        case off
        case on
        case working
        case downloading
        case error
        case uploading
        case upToDate
        case checking

        var localizedTitle: String {
            switch self {
            case .off:
                return String(localized: "Sync: Off")
            case .on:
                return String(localized: "Sync: On")
            case .working:
                return String(localized: "Sync: Working…")
            case .downloading:
                return String(localized: "Sync: Downloading…")
            case .error:
                return String(localized: "Sync: Error")
            case .uploading:
                return String(localized: "Sync: Uploading…")
            case .upToDate:
                return String(localized: "Sync: Up to date")
            case .checking:
                return String(localized: "Sync: Checking…")
            }
        }
    }

    static let shared = CloudSyncManager()

    /// Check whether the running binary was signed with the iCloud entitlement.
    /// Direct-distribution builds strip it to avoid AMFI rejection.
    private static let hasCloudKitEntitlement: Bool = {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil)
        return value != nil
        #else
        return true
        #endif
    }()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var status: SyncStatus = .off
    @Published private(set) var statusLine: String = String(localized: "Sync: Off")
    @Published private(set) var lastSyncLine: String = String(localized: "Not synced yet")
    @Published private(set) var lastErrorMessage: String?

    private weak var filterManager: AppFilterManager?

    private let logger = Logger(subsystem: "skula.wBlock", category: "CloudSync")
    private let dataManager = ProtobufDataManager.shared
    private let userScriptManager = UserScriptManager.shared

    private let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
    private lazy var database: CKDatabase? = {
        guard Self.hasCloudKitEntitlement else {
            logger.info("CloudKit unavailable (no iCloud entitlement)")
            return nil
        }
        return CKContainer.default().privateCloudDatabase
    }()
    private let recordID = CKRecord.ID(recordName: "wblock-sync-config")
    private let recordType = "wBlockSync"

    private var cancellables = Set<AnyCancellable>()
    private var pendingUploadTask: Task<Void, Never>?
    private var pendingSyncTask: Task<Void, Never>?
    private var isApplyingRemoteChanges: Bool = false
    private var uploadCoordinator = CloudSyncUploadCoordinator()
    private let deletedMarkerTTLDays: Double = 90

    private init() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        refreshStatusFromDefaults()
        observeLocalSaves()
        observeLocalUserScriptChanges()
    }

    func recordDeletedCustomListURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var markers = loadDeletedCustomURLMarkers()
        markers[trimmed] = Date().timeIntervalSince1970
        saveDeletedCustomURLMarkers(markers)
    }

    func clearDeletedCustomListURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var markers = loadDeletedCustomURLMarkers()
        markers.removeValue(forKey: trimmed)
        saveDeletedCustomURLMarkers(markers)
    }

    func recordDeletedRemoteUserScriptURL(_ urlString: String) {
        let normalized = CloudSyncRemoteUserScriptReconciler.normalizedURL(urlString)
        guard !normalized.isEmpty else { return }

        var markers = loadDeletedRemoteUserScriptURLMarkers()
        markers[normalized] = Date().timeIntervalSince1970
        saveDeletedRemoteUserScriptURLMarkers(markers)
    }

    func clearDeletedRemoteUserScriptURL(_ urlString: String) {
        let normalized = CloudSyncRemoteUserScriptReconciler.normalizedURL(urlString)
        guard !normalized.isEmpty else { return }

        var markers = loadDeletedRemoteUserScriptURLMarkers()
        markers.removeValue(forKey: normalized)
        saveDeletedRemoteUserScriptURLMarkers(markers)
    }

    func recordDeletedLocalUserScriptName(_ name: String) {
        let normalized = CloudSyncLocalUserScriptReconciler.normalizedName(name)
        guard !normalized.isEmpty else { return }

        var markers = loadDeletedLocalUserScriptMarkers()
        markers[normalized] = Date().timeIntervalSince1970
        saveDeletedLocalUserScriptMarkers(markers)
    }

    func clearDeletedLocalUserScriptName(_ name: String) {
        let normalized = CloudSyncLocalUserScriptReconciler.normalizedName(name)
        guard !normalized.isEmpty else { return }

        var markers = loadDeletedLocalUserScriptMarkers()
        markers.removeValue(forKey: normalized)
        saveDeletedLocalUserScriptMarkers(markers)
    }

    func attach(filterManager: AppFilterManager) {
        self.filterManager = filterManager
    }

    func setEnabled(_ enabled: Bool, startSync: Bool = true) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Keys.enabled)
        refreshStatusFromDefaults()

        if enabled && startSync {
            Task { await syncNow(trigger: "Enabled") }
        }
    }

    func startIfEnabled() {
        guard isEnabled else { return }
        Task {
            await dataManager.waitUntilLoaded()
            await userScriptManager.waitUntilReady()
            await syncNow(trigger: "Launch")
        }
    }

    func syncNow(trigger: String) async {
        guard isEnabled else { return }
        pendingSyncTask?.cancel()
        var task: Task<Void, Never>?
        task = Task { @MainActor [weak self] in
            defer {
                if let self, let task, self.pendingSyncTask == task {
                    self.pendingSyncTask = nil
                }
            }
            guard let self else { return }
            await self.performTwoWaySync(trigger: trigger)
        }
        pendingSyncTask = task
    }

    struct RemoteConfigProbe: Sendable {
        let exists: Bool
        let updatedAt: TimeInterval?
        let schemaVersion: Int?
    }

    func probeRemoteConfig() async -> RemoteConfigProbe {
        do {
            guard let record = try await fetchRecord() else {
                return RemoteConfigProbe(exists: false, updatedAt: nil, schemaVersion: nil)
            }
            guard let payload = try decodePayload(from: record) else {
                return RemoteConfigProbe(exists: false, updatedAt: nil, schemaVersion: nil)
            }
            return RemoteConfigProbe(
                exists: true,
                updatedAt: payload.updatedAt > 0 ? payload.updatedAt : nil,
                schemaVersion: payload.schemaVersion
            )
        } catch {
            return RemoteConfigProbe(exists: false, updatedAt: nil, schemaVersion: nil)
        }
    }

    func downloadAndApplyLatestRemoteConfig(trigger: String) async -> Bool {
        await dataManager.waitUntilLoaded()
        await userScriptManager.waitUntilReady()

        do {
            guard let record = try await fetchRecord() else { return false }
            guard let payload = try decodePayload(from: record) else { return false }

            if isSyncing { return false }
            isSyncing = true
            setStatus(.downloading)
            lastErrorMessage = nil
            defer { isSyncing = false }

            await applyRemotePayload(payload, trigger: trigger)
            logger.info("✅ Applied remote sync payload (\(trigger, privacy: .public))")
            return true
        } catch {
            setLastSyncError(error)
            setStatus(.error)
            logger.error("❌ Download/apply failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Local change tracking / upload

    private func observeLocalSaves() {
        dataManager.didSaveData
            .receive(on: RunLoop.main)
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.handleLocalSave()
            }
            .store(in: &cancellables)
    }

    private func observeLocalUserScriptChanges() {
        NotificationCenter.default.publisher(for: .userScriptManagerDidUpsertUserScript)
            .sink { [weak self] notification in
                guard let self, !self.isApplyingRemoteChanges else { return }

                let isLocal =
                    notification.userInfo?[UserScriptManagerNotificationKey.isLocal] as? Bool
                    ?? false

                if isLocal {
                    guard
                        let name = notification.userInfo?[UserScriptManagerNotificationKey.name]
                            as? String
                    else { return }
                    self.clearDeletedLocalUserScriptName(name)
                    return
                }

                guard
                    let urlString = notification.userInfo?[UserScriptManagerNotificationKey.url]
                        as? String
                else { return }
                self.clearDeletedRemoteUserScriptURL(urlString)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .userScriptManagerDidRemoveUserScript)
            .sink { [weak self] notification in
                guard let self, !self.isApplyingRemoteChanges else { return }

                let isLocal =
                    notification.userInfo?[UserScriptManagerNotificationKey.isLocal] as? Bool
                    ?? false

                if isLocal {
                    guard
                        let name = notification.userInfo?[UserScriptManagerNotificationKey.name]
                            as? String
                    else { return }
                    self.recordDeletedLocalUserScriptName(name)
                    return
                }

                guard
                    let urlString = notification.userInfo?[UserScriptManagerNotificationKey.url]
                        as? String
                else { return }
                self.recordDeletedRemoteUserScriptURL(urlString)
            }
            .store(in: &cancellables)
    }

    private func handleLocalSave() {
        guard isEnabled else { return }
        guard !isApplyingRemoteChanges else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.dataManager.waitUntilLoaded()
            await self.userScriptManager.waitUntilReady()
            self.refreshLocalSnapshotStateIfNeeded()
            self.scheduleUpload(trigger: "LocalSave")
        }
    }

    private func scheduleUpload(trigger: String) {
        switch uploadCoordinator.actionForUploadRequest(trigger: trigger, isSyncing: isSyncing) {
        case .deferUntilIdle:
            logger.info("Deferring upload until current sync finishes (\(trigger, privacy: .public))")
            return
        case let .startNow(immediateTrigger):
            pendingUploadTask?.cancel()
            var task: Task<Void, Never>?
            task = Task { @MainActor [weak self] in
                defer {
                    if let self, let task, self.pendingUploadTask == task {
                        self.pendingUploadTask = nil
                    }
                }
                guard let self else { return }
                try? await Task.sleep(for: .seconds(2))
                await self.uploadLatestPayload(trigger: immediateTrigger)
            }
            pendingUploadTask = task
        }
    }

    private func setLastSyncError(_ error: Error) {
        lastErrorMessage = userFacingErrorMessage(for: error)
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        guard let ckError = error as? CKError else {
            return error.localizedDescription
        }

        let description = ckError.localizedDescription.lowercased()
        if description.contains("pcs") || description.contains("oplock") {
            return LocalizedStrings.text(
                "iCloud Sync hit an iCloud account error. Try again in a moment. If it keeps happening, turn iCloud Sync off and back on. As a last resort, remove wBlock from iCloud settings, then re-enable sync.",
                comment: "iCloud sync account error"
            )
        }

        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return LocalizedStrings.text(
                "iCloud Sync couldn't reach iCloud. Check your connection and try again.",
                comment: "iCloud sync network error"
            )
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return LocalizedStrings.text(
                "iCloud Sync is temporarily unavailable. Try again in a moment.",
                comment: "iCloud sync temporary outage"
            )
        case .notAuthenticated:
            return LocalizedStrings.text(
                "iCloud Sync needs an active iCloud account on this device.",
                comment: "iCloud sync authentication error"
            )
        case .quotaExceeded:
            return LocalizedStrings.text(
                "iCloud Sync couldn't save because your iCloud storage is full.",
                comment: "iCloud sync quota error"
            )
        case .permissionFailure:
            return LocalizedStrings.text(
                "iCloud Sync doesn't have permission to write to your iCloud account.",
                comment: "iCloud sync permission error"
            )
        case .serverRejectedRequest, .internalError:
            return LocalizedStrings.text(
                "iCloud Sync hit an iCloud server error. Try again in a moment.",
                comment: "iCloud sync server error"
            )
        default:
            return ckError.localizedDescription
        }
    }

    private func retryDelay(for error: CKError) -> Duration? {
        if let retryAfter = error.userInfo[CKErrorRetryAfterKey] as? TimeInterval, retryAfter > 0 {
            return .milliseconds(max(250, Int(retryAfter * 1000)))
        }

        let description = error.localizedDescription.lowercased()
        if description.contains("pcs") || description.contains("oplock") {
            return .seconds(3)
        }

        switch error.code {
        case .networkUnavailable, .networkFailure:
            return .seconds(2)
        case .serviceUnavailable, .requestRateLimited, .zoneBusy, .internalError,
            .serverRejectedRequest:
            return .seconds(3)
        default:
            return nil
        }
    }

    private func uploadLatestPayload(trigger: String, withinSyncSession: Bool = false) async {
        guard isEnabled else { return }

        if !withinSyncSession {
            switch uploadCoordinator.actionForUploadRequest(trigger: trigger, isSyncing: isSyncing) {
            case .deferUntilIdle:
                logger.info("Skipping overlapping upload, queued for later (\(trigger, privacy: .public))")
                return
            case .startNow:
                isSyncing = true
                setStatus(.uploading)
            }
        }

        defer {
            if !withinSyncSession {
                finishSyncCycle()
            }
        }

        await dataManager.waitUntilLoaded()
        await userScriptManager.waitUntilReady()
        refreshLocalSnapshotStateIfNeeded()

        do {
            var record = try await fetchRecord() ?? CKRecord(recordType: recordType, recordID: recordID)

            if let remotePayload = try? decodePayload(from: record) {
                await reconcileMissingDefinitionsIfNeeded(from: remotePayload)
            }

            if defaults.double(forKey: Keys.lastLocalUpdatedAt) <= 0 {
                defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastLocalUpdatedAt)
            }

            let payload = buildPayload()
            let payloadHash = payload.contentHash

            if payloadHash == defaults.string(forKey: Keys.lastUploadedHash) {
                defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
                refreshStatusFromDefaults()
                setStatus(.upToDate)
                return
            }

            let payloadURL = try await applyPayloadFields(payload, to: &record)
            defer { try? FileManager.default.removeItem(at: payloadURL) }

            _ = try await saveRecord(record, retryPayload: payload)

            defaults.set(payloadHash, forKey: Keys.lastUploadedHash)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastUploadedAt)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
            lastErrorMessage = nil
            refreshStatusFromDefaults()

            logger.info("✅ Uploaded sync payload (\(trigger, privacy: .public))")
        } catch {
            setLastSyncError(error)
            setStatus(.error)
            logger.error("❌ Upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Two-way sync

    private func performTwoWaySync(trigger: String) async {
        guard isEnabled else { return }
        await dataManager.waitUntilLoaded()
        await userScriptManager.waitUntilReady()
        refreshLocalSnapshotStateIfNeeded()

        if isSyncing { return }
        isSyncing = true
        setStatus(.checking)
        lastErrorMessage = nil
        defer { finishSyncCycle() }

        do {
            let localPayload = buildPayload()
            let localUpdatedAt = localPayload.updatedAt

            guard let remoteRecord = try await fetchRecord() else {
                setStatus(.uploading)
                await uploadLatestPayload(trigger: "\(trigger)-NoRemote", withinSyncSession: true)
                return
            }

            guard let remotePayload = try decodePayload(from: remoteRecord) else {
                setStatus(.uploading)
                await uploadLatestPayload(trigger: "\(trigger)-BadRemote", withinSyncSession: true)
                return
            }

            if remotePayload.contentHash == localPayload.contentHash {
                defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
                refreshStatusFromDefaults()
                setStatus(.upToDate)
                return
            }

            if remotePayload.updatedAt > localUpdatedAt {
                setStatus(.downloading)
                await applyRemotePayload(remotePayload, trigger: trigger)
            } else {
                setStatus(.uploading)
                await uploadLatestPayload(trigger: "\(trigger)-LocalNewer", withinSyncSession: true)
            }
        } catch {
            setLastSyncError(error)
            setStatus(.error)
            logger.error("❌ Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyRemotePayload(_ payload: SyncPayload, trigger: String) async {
        logger.info("⬇️ Applying remote payload (\(trigger, privacy: .public))")
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        // Settings
        let autoUpdateConfigChanged = dataManager.autoUpdateEnabled != payload.settings.autoUpdateEnabled
            || dataManager.autoUpdateIntervalHours != payload.settings.autoUpdateIntervalHours
        await dataManager.setSelectedBlockingLevel(payload.settings.selectedBlockingLevel)
        await dataManager.setIsBadgeCounterEnabled(payload.settings.isBadgeCounterEnabled)
        await dataManager.setAutoUpdateEnabled(payload.settings.autoUpdateEnabled)
        await dataManager.setAutoUpdateIntervalHours(payload.settings.autoUpdateIntervalHours)
        if autoUpdateConfigChanged {
            await SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()
        }
        dataManager.setUserScriptShowEnabledOnly(payload.settings.userScriptShowEnabledOnly)
        let currentExcluded = Set(dataManager.getExcludedDefaultUserScriptURLs())
        let desiredExcluded = Set(payload.settings.excludedDefaultUserScriptURLs)
        for url in desiredExcluded.subtracting(currentExcluded) {
            dataManager.addExcludedDefaultUserScriptURL(url)
        }
        for url in currentExcluded.subtracting(desiredExcluded) {
            dataManager.removeExcludedDefaultUserScriptURL(url)
        }

        // Whitelist
        await dataManager.setWhitelistedDomains(payload.whitelistDomains)

        // Element zapper rules
        await applyRemoteZapperRules(payload.zapperRules ?? [:])

        // Filter lists (selection + custom lists)
        await applyRemoteFilters(payload.filters)

        // User scripts (remote URLs + local imports)
        await applyRemoteUserScripts(payload.userScripts)

        // Mark local state as matching the remote payload so we don't echo-upload.
        defaults.set(payload.contentHash, forKey: Keys.lastLocalHash)
        defaults.set(payload.updatedAt, forKey: Keys.lastLocalUpdatedAt)
        defaults.set(payload.contentHash, forKey: Keys.lastDownloadedHash)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastDownloadedAt)
        defaults.set(payload.contentHash, forKey: Keys.lastUploadedHash)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
        refreshStatusFromDefaults()

        // Rebuild blockers so the synced config takes effect.
        if let filterManager {
            await filterManager.applyChanges(allowUserInteraction: true)
        }
    }

    private func applyRemoteFilters(_ filters: SyncPayload.Filters) async {
        let remoteDeleted = Set(filters.deletedCustomURLs ?? [])
        let remoteCustomURLs = Set(filters.customLists.map(\.url))
        let localCustomURLs = currentLocalCustomURLs()

        let deletedURLsToClear = CloudSyncCustomFilterReconciler.deletedURLsToClearDuringReconciliation(
            existingDeletedURLs: deletedCustomURLSet(),
            remoteCustomURLs: remoteCustomURLs,
            localCustomURLs: localCustomURLs
        )
        if !deletedURLsToClear.isEmpty {
            clearDeletedCustomListURLs(deletedURLsToClear)
        }

        let remoteDeletedToMerge = CloudSyncCustomFilterReconciler.deletedURLsToMergeDuringRemoteApply(
            remoteDeletedURLs: remoteDeleted,
            remoteCustomURLs: remoteCustomURLs,
            localCustomURLs: localCustomURLs
        )
        if !remoteDeletedToMerge.isEmpty {
            mergeDeletedCustomListURLs(remoteDeletedToMerge)
        }
        let deletedCustomURLs = deletedCustomURLSet()

        let desiredSelected = Set(filters.selectedURLs)
        let knownURLs = Set(filters.knownURLs ?? filters.selectedURLs)

        if let filterManager {
            var changed = false
            var selectionChanged = false
            var nonSelectionChanged = false

            // Remove deleted custom lists (prevents resurrection + keeps UI consistent).
            if !deletedCustomURLs.isEmpty {
                let urlsToDelete = deletedCustomURLs
                let removed = filterManager.filterLists.filter { $0.isCustom && urlsToDelete.contains($0.url.absoluteString) }
                if !removed.isEmpty {
                    for list in removed {
                        Self.deleteInlineUserListContentIfNeeded(urlString: list.url.absoluteString)
                    }
                    filterManager.filterLists.removeAll { $0.isCustom && urlsToDelete.contains($0.url.absoluteString) }
                    changed = true
                    nonSelectionChanged = true
                }
            }

            // Update selection for all non-custom filters by URL
            for index in filterManager.filterLists.indices {
                guard !filterManager.filterLists[index].isCustom else { continue }
                let urlString = filterManager.filterLists[index].url.absoluteString
                guard knownURLs.contains(urlString) else { continue }
                let shouldSelect = desiredSelected.contains(urlString)
                if filterManager.filterLists[index].isSelected != shouldSelect {
                    filterManager.filterLists[index].isSelected = shouldSelect
                    changed = true
                    selectionChanged = true
                }
            }

            // Upsert custom lists from remote
            for remoteCustom in filters.customLists {
                if deletedCustomURLs.contains(remoteCustom.url) {
                    continue
                }
                if let inlineID = Self.inlineUserListID(from: remoteCustom.url) {
                    guard let content = remoteCustom.content else { continue }
                    Self.writeInlineUserListContent(id: inlineID, content: content)
                }

                if let existingIndex = filterManager.filterLists.firstIndex(where: {
                    $0.isCustom && $0.url.absoluteString == remoteCustom.url
                }) {
                    var shouldTreatAsMissing = false
                    if let inlineID = Self.inlineUserListID(from: remoteCustom.url),
                       filterManager.filterLists[existingIndex].id != inlineID
                    {
                        // Replace mismatched legacy entry (ID-based filename mismatch breaks local storage).
                        let existing = filterManager.filterLists[existingIndex]
                        filterManager.filterLists.removeAll { $0.id == existing.id }
                        changed = true
                        nonSelectionChanged = true
                        shouldTreatAsMissing = true
                    }

                    if !shouldTreatAsMissing {
                        if filterManager.filterLists[existingIndex].name != remoteCustom.name {
                            filterManager.filterLists[existingIndex].name = remoteCustom.name
                            changed = true
                            nonSelectionChanged = true
                        }
                        if let desc = remoteCustom.description,
                           filterManager.filterLists[existingIndex].description != desc
                        {
                            filterManager.filterLists[existingIndex].description = desc
                            changed = true
                            nonSelectionChanged = true
                        }
                        if filterManager.filterLists[existingIndex].isSelected != remoteCustom.isSelected {
                            filterManager.filterLists[existingIndex].isSelected = remoteCustom.isSelected
                            changed = true
                            selectionChanged = true
                        }
                    } else {
                        let newFilter = FilterList(
                            id: Self.inlineUserListID(from: remoteCustom.url) ?? UUID(),
                            name: remoteCustom.name,
                            url: URL(string: remoteCustom.url) ?? URL(string: "https://example.com")!,
                            category: .custom,
                            isCustom: true,
                            isSelected: remoteCustom.isSelected,
                            description: remoteCustom.description ?? "User-added filter list.",
                            sourceRuleCount: nil
                        )
                        filterManager.filterLists.append(newFilter)
                        changed = true
                        nonSelectionChanged = true
                    }
                } else {
                    let newFilter = FilterList(
                        id: Self.inlineUserListID(from: remoteCustom.url) ?? UUID(),
                        name: remoteCustom.name,
                        url: URL(string: remoteCustom.url) ?? URL(string: "https://example.com")!,
                        category: .custom,
                        isCustom: true,
                        isSelected: remoteCustom.isSelected,
                        description: remoteCustom.description ?? "User-added filter list.",
                        sourceRuleCount: nil
                    )
                    filterManager.filterLists.append(newFilter)
                    changed = true
                    nonSelectionChanged = true
                }
            }

            if changed {
                if nonSelectionChanged {
                    filterManager.markNonSelectionChangesPending()
                } else if selectionChanged {
                    filterManager.refreshPendingSelectionChanges()
                }
                await filterManager.saveFilterLists()
            }
            return
        }

        // Fallback: update persisted lists without touching the in-memory manager.
        var storedLists = dataManager.getFilterLists()

        if !deletedCustomURLs.isEmpty {
            storedLists.removeAll { $0.isCustom && deletedCustomURLs.contains($0.url.absoluteString) }
            for url in deletedCustomURLs {
                Self.deleteInlineUserListContentIfNeeded(urlString: url)
            }
        }

        for index in storedLists.indices where !storedLists[index].isCustom {
            let urlString = storedLists[index].url.absoluteString
            guard knownURLs.contains(urlString) else { continue }
            storedLists[index].isSelected = desiredSelected.contains(urlString)
        }

        // Upsert custom lists from remote without removing local-only customs.
        let localCustomIndexByURL: [String: Int] = Dictionary(
            uniqueKeysWithValues: storedLists.indices.compactMap { idx in
                guard storedLists[idx].isCustom else { return nil }
                return (storedLists[idx].url.absoluteString, idx)
            }
        )

        for remoteCustom in filters.customLists where !deletedCustomURLs.contains(remoteCustom.url) {
            if let inlineID = Self.inlineUserListID(from: remoteCustom.url) {
                guard let content = remoteCustom.content else { continue }
                Self.writeInlineUserListContent(id: inlineID, content: content)
            }

            if let existingIndex = localCustomIndexByURL[remoteCustom.url] {
                var updated = storedLists[existingIndex]
                if updated.name != remoteCustom.name {
                    updated.name = remoteCustom.name
                }
                if let desc = remoteCustom.description, updated.description != desc {
                    updated.description = desc
                }
                updated.isSelected = remoteCustom.isSelected
                storedLists[existingIndex] = updated
            } else {
                let newFilter = FilterList(
                    id: Self.inlineUserListID(from: remoteCustom.url) ?? UUID(),
                    name: remoteCustom.name,
                    url: URL(string: remoteCustom.url) ?? URL(string: "https://example.com")!,
                    category: .custom,
                    isCustom: true,
                    isSelected: remoteCustom.isSelected,
                    description: remoteCustom.description ?? "User-added filter list.",
                    sourceRuleCount: nil
                )
                storedLists.append(newFilter)
            }
        }

        await dataManager.updateFilterLists(storedLists)
    }

    private func applyRemoteUserScripts(_ scripts: SyncPayload.UserScripts) async {
        let remoteDeletedURLs = Set(scripts.deletedRemoteURLs ?? [])
        let remoteRemoteScriptURLs = Set(scripts.remote.map(\.url))
        let localRemoteScriptURLs = currentLocalRemoteUserScriptURLs()

        let deletedRemoteURLsToClear =
            CloudSyncRemoteUserScriptReconciler.deletedURLsToClearDuringReconciliation(
                existingDeletedURLs: deletedRemoteUserScriptURLSet(),
                remoteRemoteScriptURLs: remoteRemoteScriptURLs,
                localRemoteScriptURLs: localRemoteScriptURLs
            )
        if !deletedRemoteURLsToClear.isEmpty {
            clearDeletedRemoteUserScriptURLs(deletedRemoteURLsToClear)
        }

        let remoteDeletedURLsToMerge =
            CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringRemoteApply(
                remoteDeletedURLs: remoteDeletedURLs,
                remoteRemoteScriptURLs: remoteRemoteScriptURLs,
                localRemoteScriptURLs: localRemoteScriptURLs
            )
        if !remoteDeletedURLsToMerge.isEmpty {
            mergeDeletedRemoteUserScriptURLs(remoteDeletedURLsToMerge)
        }
        let deletedRemoteURLs = deletedRemoteUserScriptURLSet()

        if !deletedRemoteURLs.isEmpty {
            let scriptsToDelete = userScriptManager.userScripts.filter { script in
                guard !script.isLocal, let urlString = script.url?.absoluteString else {
                    return false
                }
                return deletedRemoteURLs.contains(
                    CloudSyncRemoteUserScriptReconciler.normalizedURL(urlString))
            }
            for script in scriptsToDelete {
                userScriptManager.removeUserScript(script)
            }
        }

        let remoteDeletedLocalNames = Set(scripts.deletedLocalNames ?? [])
        if !remoteDeletedLocalNames.isEmpty {
            mergeDeletedLocalUserScriptNames(remoteDeletedLocalNames)
        }

        // Remote scripts (URL-based)
        // Ensure each desired remote script exists and has the correct enabled state.
        for remote in scripts.remote {
            let normalizedURL = CloudSyncRemoteUserScriptReconciler.normalizedURL(remote.url)
            guard !normalizedURL.isEmpty, !deletedRemoteURLs.contains(normalizedURL) else {
                continue
            }
            guard let url = URL(string: remote.url) else { continue }

            if let existing = userScriptManager.userScripts.first(where: { $0.url == url }) {
                await userScriptManager.setUserScript(existing, isEnabled: remote.isEnabled)
            } else {
                await userScriptManager.addUserScript(from: url)
                if let added = userScriptManager.userScripts.first(where: { $0.url == url }) {
                    await userScriptManager.setUserScript(added, isEnabled: remote.isEnabled)
                }
            }
        }

        // Local scripts (content-based)
        // The newer remote payload is authoritative for synced local imports.
        for local in scripts.local {
            clearDeletedLocalUserScriptName(local.name)
        }

        let deletedLocalNames = deletedLocalUserScriptNameSet()
        let remoteLocalScripts = scripts.local.map {
            CloudSyncLocalUserScript(name: $0.name, content: $0.content, isEnabled: $0.isEnabled)
        }
        let localNamesToDelete = CloudSyncLocalUserScriptReconciler.localNamesToDeleteDuringRemoteApply(
            localNames: userScriptManager.userScripts.filter(\.isLocal).map(\.name),
            remoteScripts: remoteLocalScripts,
            deletedNames: deletedLocalNames
        )

        if !localNamesToDelete.isEmpty {
            let scriptsToDelete = userScriptManager.userScripts.filter { script in
                script.isLocal
                    && localNamesToDelete.contains(
                        CloudSyncLocalUserScriptReconciler.normalizedName(script.name))
            }
            for script in scriptsToDelete {
                userScriptManager.removeUserScript(script)
            }
        }

        for local in scripts.local {
            if let existing = userScriptManager.userScripts.first(where: {
                $0.isLocal
                    && CloudSyncLocalUserScriptReconciler.normalizedName($0.name)
                        == CloudSyncLocalUserScriptReconciler.normalizedName(local.name)
            }) {
                if existing.content == local.content {
                    await userScriptManager.setUserScript(existing, isEnabled: local.isEnabled)
                    continue
                }
            }

            let filename = Self.sanitizedFilename(from: local.name)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(filename).user.js")
            do {
                try local.content.write(to: tempURL, atomically: true, encoding: .utf8)
            } catch {
                continue
            }
            defer { try? FileManager.default.removeItem(at: tempURL) }

            _ = await userScriptManager.addUserScript(fromLocalFile: tempURL)

            if let imported = userScriptManager.userScripts.first(where: {
                $0.isLocal
                    && CloudSyncLocalUserScriptReconciler.normalizedName($0.name)
                        == CloudSyncLocalUserScriptReconciler.normalizedName(local.name)
            }) {
                await userScriptManager.setUserScript(imported, isEnabled: local.isEnabled)
            }
        }
    }

    private func applyRemoteZapperRules(_ zapperRules: [String: [String]]) async {
        let normalizedRemoteRules = Self.normalizedZapperRules(zapperRules)
        let currentDomains = Set(dataManager.getZapperDomains())
        let remoteDomains = Set(normalizedRemoteRules.keys)

        for domain in currentDomains.subtracting(remoteDomains) {
            await dataManager.deleteAllZapperRules(forHost: domain)
        }

        for domain in normalizedRemoteRules.keys.sorted() {
            await dataManager.setZapperRules(forHost: domain, rules: normalizedRemoteRules[domain] ?? [])
        }

        await ZapperRuleManager.shared.refreshNow()
    }

    private func reconcileMissingDefinitionsIfNeeded(from remotePayload: SyncPayload) async {
        // Import missing custom filter lists and userscripts before uploading so we don't
        // accidentally drop them from the single shared CloudKit payload.

        let localCustomURLs = currentLocalCustomURLs()
        let remoteCustomURLs = Set(remotePayload.filters.customLists.map(\.url))

        let deletedURLsToClear = CloudSyncCustomFilterReconciler.deletedURLsToClearDuringReconciliation(
            existingDeletedURLs: deletedCustomURLSet(),
            remoteCustomURLs: remoteCustomURLs,
            localCustomURLs: localCustomURLs
        )
        if !deletedURLsToClear.isEmpty {
            clearDeletedCustomListURLs(deletedURLsToClear)
        }

        let remoteDeleted = CloudSyncCustomFilterReconciler.deletedURLsToMergeDuringUploadReconciliation(
            remoteDeletedURLs: Set(remotePayload.filters.deletedCustomURLs ?? []),
            localCustomURLs: localCustomURLs.union(remoteCustomURLs)
        )
        if !remoteDeleted.isEmpty {
            mergeDeletedCustomListURLs(remoteDeleted)
        }

        let remoteDeletedLocalNames = Set(remotePayload.userScripts.deletedLocalNames ?? [])
        if !remoteDeletedLocalNames.isEmpty {
            mergeDeletedLocalUserScriptNames(remoteDeletedLocalNames)
        }

        let deletedCustomURLs = deletedCustomURLSet()
        if !deletedCustomURLs.isEmpty {
            if let filterManager {
                let urlsToDelete = deletedCustomURLs
                let removed = filterManager.filterLists.filter { $0.isCustom && urlsToDelete.contains($0.url.absoluteString) }
                if !removed.isEmpty {
                    for list in removed {
                        Self.deleteInlineUserListContentIfNeeded(urlString: list.url.absoluteString)
                    }
                    filterManager.filterLists.removeAll { $0.isCustom && urlsToDelete.contains($0.url.absoluteString) }
                    filterManager.markNonSelectionChangesPending()
                    await filterManager.saveFilterLists()
                }
            } else {
                var storedLists = dataManager.getFilterLists()
                let beforeCount = storedLists.count
                storedLists.removeAll { $0.isCustom && deletedCustomURLs.contains($0.url.absoluteString) }
                if storedLists.count != beforeCount {
                    for url in deletedCustomURLs {
                        Self.deleteInlineUserListContentIfNeeded(urlString: url)
                    }
                    await dataManager.updateFilterLists(storedLists)
                }
            }
        }

        let deletedLocalNames = deletedLocalUserScriptNameSet()
        if !deletedLocalNames.isEmpty {
            let scriptsToDelete = userScriptManager.userScripts.filter { script in
                script.isLocal
                    && deletedLocalNames.contains(
                        CloudSyncLocalUserScriptReconciler.normalizedName(script.name))
            }
            for script in scriptsToDelete {
                userScriptManager.removeUserScript(script)
            }
        }

        let remoteCustoms = remotePayload.filters.customLists
        let missingCustoms = remoteCustoms.filter {
            !deletedCustomURLs.contains($0.url) && !localCustomURLs.contains($0.url)
        }

        let localRemoteScriptURLs = currentLocalRemoteUserScriptURLs()
        let remoteRemoteScripts = remotePayload.userScripts.remote
        let remoteRemoteScriptURLs = Set(remoteRemoteScripts.map(\.url))
        let remoteDeletedRemoteURLs = Set(remotePayload.userScripts.deletedRemoteURLs ?? [])

        let deletedRemoteURLsToClear =
            CloudSyncRemoteUserScriptReconciler.deletedURLsToClearDuringReconciliation(
                existingDeletedURLs: deletedRemoteUserScriptURLSet(),
                remoteRemoteScriptURLs: remoteRemoteScriptURLs,
                localRemoteScriptURLs: localRemoteScriptURLs
            )
        if !deletedRemoteURLsToClear.isEmpty {
            clearDeletedRemoteUserScriptURLs(deletedRemoteURLsToClear)
        }

        let remoteDeletedURLsToMerge =
            CloudSyncRemoteUserScriptReconciler.deletedURLsToMergeDuringUploadReconciliation(
                remoteDeletedURLs: remoteDeletedRemoteURLs,
                localRemoteScriptURLs: localRemoteScriptURLs
            )
        if !remoteDeletedURLsToMerge.isEmpty {
            mergeDeletedRemoteUserScriptURLs(remoteDeletedURLsToMerge)
        }

        let deletedRemoteURLs = deletedRemoteUserScriptURLSet()
        if !deletedRemoteURLs.isEmpty {
            let scriptsToDelete = userScriptManager.userScripts.filter { script in
                guard !script.isLocal, let urlString = script.url?.absoluteString else {
                    return false
                }
                return deletedRemoteURLs.contains(
                    CloudSyncRemoteUserScriptReconciler.normalizedURL(urlString))
            }
            for script in scriptsToDelete {
                userScriptManager.removeUserScript(script)
            }
        }

        let missingRemoteScripts = remoteRemoteScripts.filter { remote in
            let normalizedURL = CloudSyncRemoteUserScriptReconciler.normalizedURL(remote.url)
            return !normalizedURL.isEmpty
                && !deletedRemoteURLs.contains(normalizedURL)
                && !localRemoteScriptURLs.contains(normalizedURL)
        }

        let remoteLocalScripts = remotePayload.userScripts.local
        let missingLocalScripts = CloudSyncLocalUserScriptReconciler.missingRemoteScriptsToRestore(
            remoteScripts: remoteLocalScripts.map {
                CloudSyncLocalUserScript(name: $0.name, content: $0.content, isEnabled: $0.isEnabled)
            },
            localNames: userScriptManager.userScripts.filter(\.isLocal).map(\.name),
            deletedNames: deletedLocalNames
        )

        guard !missingCustoms.isEmpty || !missingRemoteScripts.isEmpty || !missingLocalScripts.isEmpty else {
            return
        }

        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        if !missingCustoms.isEmpty {
            if let filterManager {
                var changed = false
                for remoteCustom in missingCustoms {
                    guard URL(string: remoteCustom.url) != nil else { continue }
                    if filterManager.filterLists.contains(where: { $0.isCustom && $0.url.absoluteString == remoteCustom.url }) {
                        continue
                    }
                    if let inlineID = Self.inlineUserListID(from: remoteCustom.url) {
                        guard let content = remoteCustom.content else { continue }
                        Self.writeInlineUserListContent(id: inlineID, content: content)
                    }
                    let newFilter = FilterList(
                        id: Self.inlineUserListID(from: remoteCustom.url) ?? UUID(),
                        name: remoteCustom.name,
                        url: URL(string: remoteCustom.url) ?? URL(string: "https://example.com")!,
                        category: .custom,
                        isCustom: true,
                        isSelected: remoteCustom.isSelected,
                        description: remoteCustom.description ?? "User-added filter list.",
                        sourceRuleCount: nil
                    )
                    filterManager.filterLists.append(newFilter)
                    changed = true
                }
                if changed {
                    filterManager.markNonSelectionChangesPending()
                    await filterManager.saveFilterLists()
                }
            } else {
                var storedLists = dataManager.getFilterLists()
                let existingCustomURLs = Set(storedLists.filter(\.isCustom).map { $0.url.absoluteString })
                for remoteCustom in missingCustoms where !existingCustomURLs.contains(remoteCustom.url) {
                    if let inlineID = Self.inlineUserListID(from: remoteCustom.url) {
                        guard let content = remoteCustom.content else { continue }
                        Self.writeInlineUserListContent(id: inlineID, content: content)
                    }
                    let newFilter = FilterList(
                        id: Self.inlineUserListID(from: remoteCustom.url) ?? UUID(),
                        name: remoteCustom.name,
                        url: URL(string: remoteCustom.url) ?? URL(string: "https://example.com")!,
                        category: .custom,
                        isCustom: true,
                        isSelected: remoteCustom.isSelected,
                        description: "User-added filter list.",
                        sourceRuleCount: nil
                    )
                    storedLists.append(newFilter)
                }
                await dataManager.updateFilterLists(storedLists)
            }
        }

        for remote in missingRemoteScripts {
            guard let url = URL(string: remote.url) else { continue }
            await userScriptManager.addUserScript(from: url)
            if let added = userScriptManager.userScripts.first(where: { $0.url == url }) {
                await userScriptManager.setUserScript(added, isEnabled: remote.isEnabled)
            }
        }

        for local in missingLocalScripts {
            let filename = Self.sanitizedFilename(from: local.name)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(filename).user.js")
            do {
                try local.content.write(to: tempURL, atomically: true, encoding: .utf8)
            } catch {
                continue
            }
            defer { try? FileManager.default.removeItem(at: tempURL) }

            _ = await userScriptManager.addUserScript(fromLocalFile: tempURL)
            if let imported = userScriptManager.userScripts.first(where: {
                $0.isLocal
                    && CloudSyncLocalUserScriptReconciler.normalizedName($0.name)
                        == CloudSyncLocalUserScriptReconciler.normalizedName(local.name)
            }) {
                await userScriptManager.setUserScript(imported, isEnabled: local.isEnabled)
            }
        }

        // Mark local state as changed so the upcoming upload includes the reconciled definitions.
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastLocalUpdatedAt)
        let localContent = buildPayloadContent()
        if let localContentData = try? JSONEncoder.sorted.encode(localContent) {
            defaults.set(Self.sha256Hex(localContentData), forKey: Keys.lastLocalHash)
        }
    }

    // MARK: - Payload construction

    private func buildPayload() -> SyncPayload {
        let content = buildPayloadContent()
        let updatedAt = defaults.double(forKey: Keys.lastLocalUpdatedAt)
        let contentHash = (try? JSONEncoder.sorted.encode(content)).map(Self.sha256Hex) ?? ""
        return SyncPayload(
            schemaVersion: 7,
            updatedAt: max(0, updatedAt),
            contentHash: contentHash,
            settings: content.settings,
            filters: content.filters,
            userScripts: content.userScripts,
            whitelistDomains: content.whitelistDomains,
            zapperRules: content.zapperRules
        )
    }

    private func buildPayloadContent() -> SyncPayload.Content {
        let settings = SyncPayload.Settings(
            selectedBlockingLevel: dataManager.selectedBlockingLevel,
            isBadgeCounterEnabled: dataManager.isBadgeCounterEnabled,
            autoUpdateEnabled: dataManager.autoUpdateEnabled,
            autoUpdateIntervalHours: dataManager.autoUpdateIntervalHours,
            userScriptShowEnabledOnly: dataManager.getUserScriptShowEnabledOnly(),
            excludedDefaultUserScriptURLs: dataManager.getExcludedDefaultUserScriptURLs().sorted()
        )

        let filterLists = currentFilterLists()
        let knownURLs = filterLists
            .filter { !$0.isCustom }
            .map { $0.url.absoluteString }
            .sorted()

        let selectedURLs = filterLists
            .filter { $0.isSelected }
            .map { $0.url.absoluteString }
            .sorted()

        let customLists = filterLists
            .filter(\.isCustom)
            .filter { !deletedCustomURLSet().contains($0.url.absoluteString) }
            .map { list in
                SyncPayload.CustomFilterList(
                    url: list.url.absoluteString,
                    name: list.name,
                    description: list.description.isEmpty ? nil : list.description,
                    isSelected: list.isSelected,
                    content: Self.readInlineUserListContentIfNeeded(urlString: list.url.absoluteString)
                )
            }
            .sorted { $0.url < $1.url }

        let deletedCustomURLs = Array(deletedCustomURLSet()).sorted()

        let filters = SyncPayload.Filters(
            knownURLs: knownURLs,
            selectedURLs: selectedURLs,
            customLists: customLists,
            deletedCustomURLs: deletedCustomURLs.isEmpty ? nil : deletedCustomURLs
        )

        let remoteScripts = userScriptManager.userScripts
            .filter { !$0.isLocal && $0.url != nil }
            .compactMap { script -> SyncPayload.RemoteUserScript? in
                guard let url = script.url else { return nil }
                return SyncPayload.RemoteUserScript(url: url.absoluteString, isEnabled: script.isEnabled)
            }
            .sorted { $0.url < $1.url }

        let localScripts = userScriptManager.userScripts
            .filter { $0.isLocal }
            .map { script in
                SyncPayload.LocalUserScript(name: script.name, content: script.content, isEnabled: script.isEnabled)
            }
            .sorted { $0.name < $1.name }

        let deletedLocalNames = Array(deletedLocalUserScriptNameSet()).sorted()
        let deletedRemoteURLs = Array(deletedRemoteUserScriptURLSet()).sorted()
        let userScripts = SyncPayload.UserScripts(
            remote: remoteScripts,
            local: localScripts,
            deletedLocalNames: deletedLocalNames.isEmpty ? nil : deletedLocalNames,
            deletedRemoteURLs: deletedRemoteURLs.isEmpty ? nil : deletedRemoteURLs
        )

        let whitelistDomains = dataManager.getWhitelistedDomains().sorted()
        let zapperRules = Self.normalizedZapperRules(
            Dictionary(
                uniqueKeysWithValues: dataManager.getZapperDomains().map { domain in
                    (domain, dataManager.getZapperRules(forHost: domain))
                }
            )
        )

        return SyncPayload.Content(
            settings: settings,
            filters: filters,
            userScripts: userScripts,
            whitelistDomains: whitelistDomains,
            zapperRules: zapperRules
        )
    }

    private func currentFilterLists() -> [FilterList] {
        if let filterManager {
            return filterManager.filterLists
        }
        return dataManager.getFilterLists()
    }

    private func currentLocalCustomURLs() -> Set<String> {
        Set(currentFilterLists().filter(\.isCustom).map { $0.url.absoluteString })
    }

    private func currentLocalRemoteUserScriptURLs() -> Set<String> {
        Set(
            userScriptManager.userScripts.compactMap { script in
                guard !script.isLocal, let url = script.url else { return nil }
                let normalized = CloudSyncRemoteUserScriptReconciler.normalizedURL(
                    url.absoluteString)
                return normalized.isEmpty ? nil : normalized
            }
        )
    }

    private func refreshLocalSnapshotStateIfNeeded() {
        let localContent = buildPayloadContent()
        guard let localContentData = try? JSONEncoder.sorted.encode(localContent) else { return }
        let localHash = Self.sha256Hex(localContentData)

        if localHash != defaults.string(forKey: Keys.lastLocalHash) {
            defaults.set(localHash, forKey: Keys.lastLocalHash)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastLocalUpdatedAt)
        }
    }

    private static func normalizedZapperRules(_ rulesByDomain: [String: [String]]) -> [String: [String]] {
        var normalized: [String: [String]] = [:]

        for (domain, rules) in rulesByDomain {
            let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDomain.isEmpty else { continue }

            let cleanedRules = Array(
                Set(
                    rules.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            ).sorted()

            if !cleanedRules.isEmpty {
                normalized[trimmedDomain] = cleanedRules
            }
        }

        return normalized
    }

    // MARK: - CloudKit I/O

    private func fetchRecord() async throws -> CKRecord? {
        guard let database else { throw CloudSyncError.cloudKitUnavailable }
        do {
            return try await withCheckedThrowingContinuation { continuation in
                database.fetch(withRecordID: recordID) { record, error in
                    if let error {
                        if let ckError = error as? CKError, ckError.code == .unknownItem {
                            continuation.resume(returning: nil)
                            return
                        }
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: record)
                }
            }
        } catch {
            throw error
        }
    }

    private func saveRecord(
        _ record: CKRecord,
        retryPayload: SyncPayload? = nil,
        retryCount: Int = 0
    ) async throws -> CKRecord {
        guard let database else { throw CloudSyncError.cloudKitUnavailable }
        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
                database.save(record) { saved, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: saved ?? record)
                }
            }
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            guard let retryPayload, let serverRecord = ckError.serverRecord else { throw ckError }
            logger.info("Server record changed, retrying save with server version")
            var mutableRecord = serverRecord
            let payloadURL = try await applyPayloadFields(retryPayload, to: &mutableRecord)
            defer { try? FileManager.default.removeItem(at: payloadURL) }
            return try await saveRecord(
                mutableRecord,
                retryPayload: retryPayload,
                retryCount: retryCount
            )
        } catch let ckError as CKError {
            guard retryCount < 2, let delay = retryDelay(for: ckError) else { throw ckError }
            logger.info(
                "CloudKit save failed with retryable error \(ckError.code.rawValue, privacy: .public), retrying in \(String(describing: delay), privacy: .public)"
            )
            try await Task.sleep(for: delay)
            return try await saveRecord(
                record,
                retryPayload: retryPayload,
                retryCount: retryCount + 1
            )
        }
    }

    private func applyPayloadFields(_ payload: SyncPayload, to record: inout CKRecord) async throws -> URL {
        let data = try JSONEncoder.sorted.encode(payload)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-sync-\(UUID().uuidString).json")
        try data.write(to: tempURL, options: .atomic)

        record["schemaVersion"] = payload.schemaVersion as CKRecordValue
        record["updatedAt"] = Date(timeIntervalSince1970: payload.updatedAt) as CKRecordValue
        record["contentHash"] = payload.contentHash as CKRecordValue
        record["payload"] = CKAsset(fileURL: tempURL)
        return tempURL
    }

    private func decodePayload(from record: CKRecord) throws -> SyncPayload? {
        guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SyncPayload.self, from: data)
    }

    // MARK: - Status

    private func refreshStatusFromDefaults() {
        if !isEnabled {
            setStatus(.off)
            lastSyncLine = String(localized: "Not synced yet")
            return
        }

        setStatus(isSyncing ? .working : .on)

        let lastSyncAt = defaults.double(forKey: Keys.lastSyncAt)
        if lastSyncAt > 0 {
            lastSyncLine = CloudSyncTimestampFormatter.lastSyncLine(
                for: Date(timeIntervalSince1970: lastSyncAt)
            )
        } else {
            lastSyncLine = String(localized: "Not synced yet")
        }
    }

    private func setStatus(_ status: SyncStatus) {
        self.status = status
        statusLine = status.localizedTitle
    }

    // MARK: - Helpers

    private func finishSyncCycle() {
        isSyncing = false

        guard let deferredTrigger = uploadCoordinator.takeDeferredTrigger() else { return }
        logger.info("Scheduling deferred upload (\(deferredTrigger, privacy: .public))")
        scheduleUpload(trigger: deferredTrigger)
    }

    private enum Keys {
        static let enabled = "cloudSyncEnabled"
        static let lastLocalHash = "cloudSyncLastLocalHash"
        static let lastLocalUpdatedAt = "cloudSyncLastLocalUpdatedAt"
        static let lastUploadedHash = "cloudSyncLastUploadedHash"
        static let lastUploadedAt = "cloudSyncLastUploadedAt"
        static let lastDownloadedHash = "cloudSyncLastDownloadedHash"
        static let lastDownloadedAt = "cloudSyncLastDownloadedAt"
        static let lastSyncAt = "cloudSyncLastSyncAt"
        static let deletedCustomURLs = "cloudSyncDeletedCustomURLs"
        static let deletedLocalUserScriptNames = "cloudSyncDeletedLocalUserScriptNames"
        static let deletedRemoteUserScriptURLs = "cloudSyncDeletedRemoteUserScriptURLs"
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sanitizedFilename(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Userscript" }
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_()[]"))
        let filtered = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(filtered).prefix(60).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inlineUserListID(from urlString: String) -> UUID? {
        guard let url = URL(string: urlString) else { return nil }
        guard url.scheme?.lowercased() == "wblock" else { return nil }
        guard url.host?.lowercased() == "userlist" else { return nil }
        let idString = url.pathComponents.dropFirst().first
        guard let idString, let id = UUID(uuidString: idString) else { return nil }
        return id
    }

    private static func readInlineUserListContentIfNeeded(urlString: String) -> String? {
        guard let id = inlineUserListID(from: urlString) else { return nil }
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            return nil
        }
        let fileURL = containerURL.appendingPathComponent("custom-\(id.uuidString).txt")
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    private static func writeInlineUserListContent(id: UUID, content: String) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            return
        }
        let fileURL = containerURL.appendingPathComponent("custom-\(id.uuidString).txt")
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            Logger(subsystem: "skula.wBlock", category: "CloudSync").error(
                "Failed writing inline user list content: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func deleteInlineUserListContentIfNeeded(urlString: String) {
        guard let id = inlineUserListID(from: urlString) else { return }
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            return
        }
        let fileURL = containerURL.appendingPathComponent("custom-\(id.uuidString).txt")
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func deletedCustomURLSet() -> Set<String> {
        let markers = loadDeletedCustomURLMarkers()
        return Set(markers.keys)
    }

    private func loadDeletedCustomURLMarkers() -> [String: TimeInterval] {
        let raw = defaults.dictionary(forKey: Keys.deletedCustomURLs) ?? [:]
        var result: [String: TimeInterval] = [:]
        for (key, value) in raw {
            if let t = value as? TimeInterval {
                result[key] = t
            } else if let d = value as? Double {
                result[key] = d
            } else if let n = value as? NSNumber {
                result[key] = n.doubleValue
            }
        }

        let pruned = pruneDeletedCustomURLMarkers(result)
        if pruned.count != result.count {
            saveDeletedCustomURLMarkers(pruned)
        }
        return pruned
    }

    private func pruneDeletedCustomURLMarkers(_ markers: [String: TimeInterval]) -> [String: TimeInterval] {
        let ttl = deletedMarkerTTLDays * 24 * 60 * 60
        let now = Date().timeIntervalSince1970
        return markers.filter { _, deletedAt in
            deletedAt > 0 && (now - deletedAt) <= ttl
        }
    }

    private func saveDeletedCustomURLMarkers(_ markers: [String: TimeInterval]) {
        let pruned = pruneDeletedCustomURLMarkers(markers)
        defaults.set(pruned, forKey: Keys.deletedCustomURLs)
    }

    private func clearDeletedCustomListURLs(_ urls: Set<String>) {
        guard !urls.isEmpty else { return }
        var markers = loadDeletedCustomURLMarkers()
        var changed = false
        for url in urls {
            let normalized = CloudSyncCustomFilterReconciler.normalizedURL(url)
            guard !normalized.isEmpty else { continue }
            if markers.removeValue(forKey: normalized) != nil {
                changed = true
            }
        }
        if changed {
            saveDeletedCustomURLMarkers(markers)
        }
    }

    private func mergeDeletedCustomListURLs(_ urls: Set<String>) {
        guard !urls.isEmpty else { return }
        var markers = loadDeletedCustomURLMarkers()
        let now = Date().timeIntervalSince1970
        for url in urls {
            if markers[url] == nil {
                markers[url] = now
            }
        }
        saveDeletedCustomURLMarkers(markers)
    }

    private func deletedLocalUserScriptNameSet() -> Set<String> {
        let markers = loadDeletedLocalUserScriptMarkers()
        return Set(markers.keys)
    }

    private func loadDeletedLocalUserScriptMarkers() -> [String: TimeInterval] {
        let raw = defaults.dictionary(forKey: Keys.deletedLocalUserScriptNames) ?? [:]
        var result: [String: TimeInterval] = [:]
        for (key, value) in raw {
            let normalized = CloudSyncLocalUserScriptReconciler.normalizedName(key)
            guard !normalized.isEmpty else { continue }
            if let t = value as? TimeInterval {
                result[normalized] = t
            } else if let d = value as? Double {
                result[normalized] = d
            } else if let n = value as? NSNumber {
                result[normalized] = n.doubleValue
            }
        }

        let pruned = pruneDeletedLocalUserScriptMarkers(result)
        if pruned.count != result.count {
            saveDeletedLocalUserScriptMarkers(pruned)
        }
        return pruned
    }

    private func pruneDeletedLocalUserScriptMarkers(_ markers: [String: TimeInterval]) -> [String: TimeInterval] {
        let ttl = deletedMarkerTTLDays * 24 * 60 * 60
        let now = Date().timeIntervalSince1970
        return markers.filter { _, deletedAt in
            deletedAt > 0 && (now - deletedAt) <= ttl
        }
    }

    private func saveDeletedLocalUserScriptMarkers(_ markers: [String: TimeInterval]) {
        let pruned = pruneDeletedLocalUserScriptMarkers(markers)
        defaults.set(pruned, forKey: Keys.deletedLocalUserScriptNames)
    }

    private func mergeDeletedLocalUserScriptNames(_ names: Set<String>) {
        guard !names.isEmpty else { return }
        var markers = loadDeletedLocalUserScriptMarkers()
        let now = Date().timeIntervalSince1970
        for name in names {
            let normalized = CloudSyncLocalUserScriptReconciler.normalizedName(name)
            guard !normalized.isEmpty else { continue }
            if markers[normalized] == nil {
                markers[normalized] = now
            }
        }
        saveDeletedLocalUserScriptMarkers(markers)
    }

    private func deletedRemoteUserScriptURLSet() -> Set<String> {
        let markers = loadDeletedRemoteUserScriptURLMarkers()
        return Set(markers.keys)
    }

    private func loadDeletedRemoteUserScriptURLMarkers() -> [String: TimeInterval] {
        let raw = defaults.dictionary(forKey: Keys.deletedRemoteUserScriptURLs) ?? [:]
        var result: [String: TimeInterval] = [:]
        for (key, value) in raw {
            let normalized = CloudSyncRemoteUserScriptReconciler.normalizedURL(key)
            guard !normalized.isEmpty else { continue }
            if let t = value as? TimeInterval {
                result[normalized] = t
            } else if let d = value as? Double {
                result[normalized] = d
            } else if let n = value as? NSNumber {
                result[normalized] = n.doubleValue
            }
        }

        let pruned = pruneDeletedRemoteUserScriptURLMarkers(result)
        if pruned.count != result.count {
            saveDeletedRemoteUserScriptURLMarkers(pruned)
        }
        return pruned
    }

    private func pruneDeletedRemoteUserScriptURLMarkers(_ markers: [String: TimeInterval]) -> [String: TimeInterval] {
        let ttl = deletedMarkerTTLDays * 24 * 60 * 60
        let now = Date().timeIntervalSince1970
        return markers.filter { _, deletedAt in
            deletedAt > 0 && (now - deletedAt) <= ttl
        }
    }

    private func saveDeletedRemoteUserScriptURLMarkers(_ markers: [String: TimeInterval]) {
        let pruned = pruneDeletedRemoteUserScriptURLMarkers(markers)
        defaults.set(pruned, forKey: Keys.deletedRemoteUserScriptURLs)
    }

    private func clearDeletedRemoteUserScriptURLs(_ urls: Set<String>) {
        guard !urls.isEmpty else { return }
        var markers = loadDeletedRemoteUserScriptURLMarkers()
        for url in urls {
            let normalized = CloudSyncRemoteUserScriptReconciler.normalizedURL(url)
            guard !normalized.isEmpty else { continue }
            markers.removeValue(forKey: normalized)
        }
        saveDeletedRemoteUserScriptURLMarkers(markers)
    }

    private func mergeDeletedRemoteUserScriptURLs(_ urls: Set<String>) {
        guard !urls.isEmpty else { return }
        var markers = loadDeletedRemoteUserScriptURLMarkers()
        let now = Date().timeIntervalSince1970
        for url in urls {
            let normalized = CloudSyncRemoteUserScriptReconciler.normalizedURL(url)
            guard !normalized.isEmpty else { continue }
            if markers[normalized] == nil {
                markers[normalized] = now
            }
        }
        saveDeletedRemoteUserScriptURLMarkers(markers)
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private struct SyncPayload: Codable {
    struct Settings: Codable {
        let selectedBlockingLevel: String
        let isBadgeCounterEnabled: Bool
        let autoUpdateEnabled: Bool
        let autoUpdateIntervalHours: Double
        let userScriptShowEnabledOnly: Bool
        let excludedDefaultUserScriptURLs: [String]
    }

    struct CustomFilterList: Codable {
        let url: String
        let name: String
        let description: String?
        let isSelected: Bool
        /// Inline user list content (for wblock://userlist/<uuid> lists). Nil for URL-hosted lists.
        let content: String?
    }

    struct Filters: Codable {
        /// All non-custom filters known on the uploading device. Used to avoid cross-platform
        /// state overrides for platform-only filters when syncing.
        let knownURLs: [String]?
        let selectedURLs: [String]
        let customLists: [CustomFilterList]
        /// Custom list URLs deleted by the user. Used to prevent resurrection during sync.
        let deletedCustomURLs: [String]?
    }

    struct RemoteUserScript: Codable {
        let url: String
        let isEnabled: Bool
    }

    struct LocalUserScript: Codable {
        let name: String
        let content: String
        let isEnabled: Bool
    }

    struct UserScripts: Codable {
        let remote: [RemoteUserScript]
        let local: [LocalUserScript]
        let deletedLocalNames: [String]?
        let deletedRemoteURLs: [String]?
    }

    struct Content: Codable {
        let settings: Settings
        let filters: Filters
        let userScripts: UserScripts
        let whitelistDomains: [String]
        let zapperRules: [String: [String]]?
    }

    let schemaVersion: Int
    let updatedAt: TimeInterval
    let contentHash: String
    let settings: Settings
    let filters: Filters
    let userScripts: UserScripts
    let whitelistDomains: [String]
    let zapperRules: [String: [String]]?
}
