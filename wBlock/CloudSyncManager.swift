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
    private var hasActivatedObservers = false
    private var hasCompletedLaunchSetup = false
    private var deferredSyncTrigger: String?
    private var hasPendingExplicitRemoteDownload = false
    private var pendingUploadTask: Task<Void, Never>?
    private var pendingSyncTask: Task<Void, Never>?
    private var isApplyingRemoteChanges: Bool = false
    private var uploadCoordinator = CloudSyncUploadCoordinator()
    private let deletedMarkerTTLDays: Double = 90

    private init() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        refreshStatusFromDefaults()
    }

    func activateAfterLaunchSetup() {
        guard !hasActivatedObservers else { return }
        hasActivatedObservers = true
        hasCompletedLaunchSetup = true
        observeLocalSaves()
        observeLocalUserScriptChanges()

        let trigger = deferredSyncTrigger ?? ((isEnabled && !hasPendingExplicitRemoteDownload) ? "Launch" : nil)
        deferredSyncTrigger = nil
        guard let trigger else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncNow(trigger: trigger)
        }
    }

    private func waitUntilLaunchSetupComplete() async {
        while !hasCompletedLaunchSetup {
            await Task.yield()
        }
    }

    func recordDeletedCustomListURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mergeDeletedMarkers([trimmed], markers: loadDeletedCustomURLMarkers(), saveKey: Keys.deletedCustomURLs)
    }

    func clearDeletedCustomListURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        clearDeletedMarkers([trimmed], markers: loadDeletedCustomURLMarkers(), saveKey: Keys.deletedCustomURLs)
    }

    func recordDeletedRemoteUserScriptURL(_ urlString: String) {
        let normalized = CloudSyncRemoteUserScriptReconciler.normalizedURL(urlString)
        guard !normalized.isEmpty else { return }
        mergeDeletedMarkers([normalized], markers: loadDeletedRemoteUserScriptURLMarkers(), saveKey: Keys.deletedRemoteUserScriptURLs)
    }

    func clearDeletedRemoteUserScriptURL(_ urlString: String) {
        let normalized = CloudSyncRemoteUserScriptReconciler.normalizedURL(urlString)
        guard !normalized.isEmpty else { return }
        clearDeletedMarkers([normalized], markers: loadDeletedRemoteUserScriptURLMarkers(), saveKey: Keys.deletedRemoteUserScriptURLs)
    }

    func recordDeletedLocalUserScriptName(_ name: String) {
        let normalized = CloudSyncLocalUserScriptReconciler.normalizedName(name)
        guard !normalized.isEmpty else { return }
        mergeDeletedMarkers([normalized], markers: loadDeletedLocalUserScriptMarkers(), saveKey: Keys.deletedLocalUserScriptNames)
    }

    func clearDeletedLocalUserScriptName(_ name: String) {
        let normalized = CloudSyncLocalUserScriptReconciler.normalizedName(name)
        guard !normalized.isEmpty else { return }
        clearDeletedMarkers([normalized], markers: loadDeletedLocalUserScriptMarkers(), saveKey: Keys.deletedLocalUserScriptNames)
    }

    private func clearDeletedLocalUserScriptNames(_ names: Set<String>) {
        let normalizedNames = Set(names.map(CloudSyncLocalUserScriptReconciler.normalizedName).filter { !$0.isEmpty })
        let markers = loadDeletedLocalUserScriptMarkers()
        clearDeletedMarkers(normalizedNames, markers: markers, saveKey: Keys.deletedLocalUserScriptNames)
    }

    func attach(filterManager: AppFilterManager) {
        self.filterManager = filterManager
    }

    func setEnabled(_ enabled: Bool, startSync: Bool = true) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Keys.enabled)
        refreshStatusFromDefaults()

        if !enabled {
            deferredSyncTrigger = nil
            return
        }

        if startSync {
            guard hasCompletedLaunchSetup else {
                deferredSyncTrigger = "Enabled"
                return
            }
            Task { await syncNow(trigger: "Enabled") }
        }
    }

    func startIfEnabled() {
        guard isEnabled else { return }
        guard hasCompletedLaunchSetup else {
            deferredSyncTrigger = "Launch"
            return
        }

        Task {
            await dataManager.waitUntilLoaded()
            await userScriptManager.waitUntilReady()
            await syncNow(trigger: "Launch")
        }
    }

    func syncNow(trigger: String) async {
        guard isEnabled else { return }
        guard hasCompletedLaunchSetup else {
            deferredSyncTrigger = trigger
            return
        }

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
            // updatedAt and schemaVersion are stored as top-level record fields, so the
            // probe can answer without downloading the payload asset.
            let updatedAt = (record["updatedAt"] as? Date)?.timeIntervalSince1970
            let schemaVersion = record["schemaVersion"] as? Int
            return RemoteConfigProbe(
                exists: true,
                updatedAt: (updatedAt ?? 0) > 0 ? updatedAt : nil,
                schemaVersion: schemaVersion
            )
        } catch {
            return RemoteConfigProbe(exists: false, updatedAt: nil, schemaVersion: nil)
        }
    }

    func downloadAndApplyLatestRemoteConfig(trigger: String) async -> Bool {
        if !hasCompletedLaunchSetup {
            hasPendingExplicitRemoteDownload = true
            defer { hasPendingExplicitRemoteDownload = false }
            await waitUntilLaunchSetupComplete()
        }

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
                try? await TaskSleep.sleep(for: .seconds(2))
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

    private func retryDelay(for error: CKError) -> AsyncDelay? {
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
                // Already uploaded, so every current local script name is known-synced.
                setLastSyncedLocalUserScriptNames(localUserScriptNames(in: payload))
                defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
                refreshStatusFromDefaults()
                setStatus(.upToDate)
                return
            }

            let payloadURL = try await applyPayloadFields(payload, to: &record)
            defer { try? FileManager.default.removeItem(at: payloadURL) }

            let savedPayload = try await saveRecordWithConflictResolution(record, payload: payload)

            defaults.set(savedPayload.contentHash, forKey: Keys.lastUploadedHash)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastUploadedAt)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
            // The uploaded payload's local script names are now known-synced.
            setLastSyncedLocalUserScriptNames(localUserScriptNames(in: savedPayload))
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

            // contentHash and updatedAt are stored as top-level record fields, so compare
            // them before downloading the payload asset. Decoding the asset is deferred until
            // we actually have to apply the remote payload, which makes the common
            // "nothing changed" / "local is newer" paths metadata-only fetches.
            let remoteContentHash = remoteRecord["contentHash"] as? String
            let remoteRecordUpdatedAt = (remoteRecord["updatedAt"] as? Date)?.timeIntervalSince1970

            if let remoteContentHash, remoteContentHash == localPayload.contentHash {
                markUpToDate(from: localPayload)
                return
            }

            // Decide direction. With record fields the stored updatedAt tells us; legacy
            // records without fields fall back to decoding the asset to compare reliably.
            let remoteIsNewer: Bool
            var legacyPayload: SyncPayload?
            if let remoteRecordUpdatedAt {
                remoteIsNewer = remoteRecordUpdatedAt > localUpdatedAt
            } else {
                guard let decoded = try decodePayload(from: remoteRecord) else {
                    setStatus(.uploading)
                    await uploadLatestPayload(trigger: "\(trigger)-BadRemote", withinSyncSession: true)
                    return
                }
                legacyPayload = decoded
                remoteIsNewer = decoded.updatedAt > localUpdatedAt
                if decoded.contentHash == localPayload.contentHash {
                    markUpToDate(from: localPayload)
                    return
                }
            }

            if remoteIsNewer {
                let remotePayload: SyncPayload
                if let legacyPayload {
                    remotePayload = legacyPayload
                } else {
                    guard let decoded = try decodePayload(from: remoteRecord) else {
                        setStatus(.uploading)
                        await uploadLatestPayload(trigger: "\(trigger)-BadRemote", withinSyncSession: true)
                        return
                    }
                    remotePayload = decoded
                }
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
        await dataManager.setFilterDisabledDomains(payload.filterDisabledDomains ?? [])

        // Element zapper rules
        await applyRemoteZapperRules(payload.zapperRules ?? [:], disabledDomains: payload.zapperDisabledDomains)

        await applyRemoteFilters(payload.filters, remoteUpdatedAt: payload.updatedAt)

        // User scripts (remote URLs + local imports)
        let keptUnsyncedLocalScripts = await applyRemoteUserScripts(payload.userScripts)

        // Record the local script names that are now known-synced (present in the cloud payload).
        // Kept-but-never-synced local scripts are intentionally excluded here; they become synced
        // only after the follow-up upload below pushes them to the cloud.
        setLastSyncedLocalUserScriptNames(localUserScriptNames(in: payload))

        // Mark local state as matching the remote payload so we don't echo-upload.
        defaults.set(payload.contentHash, forKey: Keys.lastLocalHash)
        defaults.set(payload.updatedAt, forKey: Keys.lastLocalUpdatedAt)
        defaults.set(payload.contentHash, forKey: Keys.lastDownloadedHash)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastDownloadedAt)
        defaults.set(payload.contentHash, forKey: Keys.lastUploadedHash)
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
        refreshStatusFromDefaults()

        // A local userscript that was never synced and isn't in the winning remote payload was
        // kept rather than deleted. Schedule an upload so it propagates to the cloud (#437). The
        // request is deferred while syncing and picked up by finishSyncCycle().
        if keptUnsyncedLocalScripts {
            scheduleUpload(trigger: "\(trigger)-KeepUnsyncedLocal")
        }

        // Rebuild blockers so the synced config takes effect.
        if let filterManager {
            await filterManager.applyChanges(allowUserInteraction: true)
        }
    }

    private func applyRemoteFilters(_ filters: SyncPayload.Filters, remoteUpdatedAt: TimeInterval) async {
        let remoteDeleted = Set(filters.deletedCustomURLs ?? [])
        let remoteCustomURLs = Set(filters.customLists.map(\.url))
        let localCustomURLs = currentLocalCustomURLs()

        let deletedURLsToClear = CloudSyncCustomFilterReconciler.deletedURLsToClearDuringReconciliation(
            existingDeletedURLMarkers: loadDeletedCustomURLMarkers(),
            remoteCustomURLs: remoteCustomURLs,
            localCustomURLs: localCustomURLs,
            remoteUpdatedAt: remoteUpdatedAt
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
                let remoteCategory = remoteCustom.resolvedCategory
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
                        if filterManager.filterLists[existingIndex].category != remoteCategory {
                            filterManager.filterLists[existingIndex].category = remoteCategory
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
                            category: remoteCategory,
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
                        category: remoteCategory,
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
            let remoteCategory = remoteCustom.resolvedCategory
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
                if updated.category != remoteCategory {
                    updated.category = remoteCategory
                }
                updated.isSelected = remoteCustom.isSelected
                storedLists[existingIndex] = updated
            } else {
                let newFilter = FilterList(
                    id: Self.inlineUserListID(from: remoteCustom.url) ?? UUID(),
                    name: remoteCustom.name,
                    url: URL(string: remoteCustom.url) ?? URL(string: "https://example.com")!,
                    category: remoteCategory,
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

    @discardableResult
    private func applyRemoteUserScripts(_ scripts: SyncPayload.UserScripts) async -> Bool {
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
        let localNames = userScriptManager.userScripts.filter(\.isLocal).map(\.name)
        let remoteLocalScripts = scripts.local.map {
            CloudSyncLocalUserScript(
                name: $0.name,
                content: $0.content,
                isEnabled: $0.isEnabled,
                updatesAutomatically: $0.updatesAutomatically
            )
        }

        let deletedLocalNamesToClear =
            CloudSyncLocalUserScriptReconciler.deletedNamesToClearDuringReconciliation(
                existingDeletedNames: deletedLocalUserScriptNameSet(),
                remoteLocalScripts: remoteLocalScripts,
                localNames: localNames
            )
        if !deletedLocalNamesToClear.isEmpty {
            clearDeletedLocalUserScriptNames(deletedLocalNamesToClear)
        }

        let remoteDeletedLocalNamesToMerge =
            CloudSyncLocalUserScriptReconciler.deletedNamesToMergeDuringRemoteApply(
                remoteDeletedNames: remoteDeletedLocalNames,
                remoteLocalScripts: remoteLocalScripts,
                localNames: localNames
            )
        if !remoteDeletedLocalNamesToMerge.isEmpty {
            mergeDeletedLocalUserScriptNames(remoteDeletedLocalNamesToMerge)
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
                await userScriptManager.setUserScript(existing, updatesAutomatically: remote.resolvedUpdatesAutomatically)
            } else {
                await userScriptManager.addUserScript(from: url)
                if let added = userScriptManager.userScripts.first(where: { $0.url == url }) {
                    await userScriptManager.setUserScript(added, isEnabled: remote.isEnabled)
                    await userScriptManager.setUserScript(added, updatesAutomatically: remote.resolvedUpdatesAutomatically)
                }
            }
        }

        // Local scripts (content-based)
        // The newer remote payload is authoritative for synced local imports.

        let deletedLocalNames = deletedLocalUserScriptNameSet()
        let lastSyncedNames = lastSyncedLocalUserScriptNameSet()
        let currentLocalNames = userScriptManager.userScripts.filter(\.isLocal).map(\.name)
        let localNamesToDelete = CloudSyncLocalUserScriptReconciler.localNamesToDeleteDuringRemoteApply(
            localNames: currentLocalNames,
            remoteScripts: remoteLocalScripts,
            deletedNames: deletedLocalNames,
            lastSyncedNames: lastSyncedNames
        )
        let keptUnsyncedLocalNames = CloudSyncLocalUserScriptReconciler.localNamesNeverSyncedToUpload(
            localNames: currentLocalNames,
            remoteScripts: remoteLocalScripts,
            deletedNames: deletedLocalNames,
            lastSyncedNames: lastSyncedNames
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
                    await userScriptManager.setUserScript(existing, updatesAutomatically: local.resolvedUpdatesAutomatically)
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
                await userScriptManager.setUserScript(imported, updatesAutomatically: local.resolvedUpdatesAutomatically)
            }
        }

        for remote in scripts.remote {
            guard let disabledHosts = remote.disabledHosts else { continue }
            guard let url = URL(string: remote.url) else { continue }
            guard let script = userScriptManager.userScripts.first(where: { $0.url == url }) else { continue }
            await dataManager.setUserScriptDisabledHosts(disabledHosts, forScriptID: script.id.uuidString)
        }

        for local in scripts.local {
            guard let disabledHosts = local.disabledHosts else { continue }
            guard let script = userScriptManager.userScripts.first(where: {
                $0.isLocal
                    && CloudSyncLocalUserScriptReconciler.normalizedName($0.name)
                        == CloudSyncLocalUserScriptReconciler.normalizedName(local.name)
            }) else {
                continue
            }
            await dataManager.setUserScriptDisabledHosts(disabledHosts, forScriptID: script.id.uuidString)
        }

        // Report whether any never-synced local scripts were kept so the caller can schedule an
        // upload to propagate them to the cloud (#437).
        return !keptUnsyncedLocalNames.isEmpty
    }

    private func applyRemoteZapperRules(_ zapperRules: [String: [String]], disabledDomains: [String]?) async {
        let normalizedRemoteRules = Self.normalizedZapperRules(zapperRules)
        let currentDomains = Set(dataManager.getZapperDomains())
        let remoteDomains = Set(normalizedRemoteRules.keys)

        for domain in currentDomains.subtracting(remoteDomains) {
            await dataManager.deleteAllZapperRules(forHost: domain)
        }

        for domain in normalizedRemoteRules.keys.sorted() {
            await dataManager.setZapperRules(forHost: domain, rules: normalizedRemoteRules[domain] ?? [])
        }

        if let disabledDomains {
            let disabledDomainSet = Set(Self.normalizedDisabledHosts(disabledDomains))
            for domain in normalizedRemoteRules.keys.sorted() {
                await dataManager.setZapperRulesDisabled(disabledDomainSet.contains(domain), forHost: domain)
            }
        }

        await ZapperRuleManager.shared.refreshNow()
    }

    private func reconcileMissingDefinitionsIfNeeded(from remotePayload: SyncPayload) async {
        // Import missing custom filter lists and userscripts before uploading so we don't
        // accidentally drop them from the single shared CloudKit payload.

        let localCustomURLs = currentLocalCustomURLs()
        let remoteCustomURLs = Set(remotePayload.filters.customLists.map(\.url))

        let deletedURLsToClear = CloudSyncCustomFilterReconciler.deletedURLsToClearDuringReconciliation(
            existingDeletedURLMarkers: loadDeletedCustomURLMarkers(),
            remoteCustomURLs: remoteCustomURLs,
            localCustomURLs: localCustomURLs,
            remoteUpdatedAt: remotePayload.updatedAt
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
        let localNames = userScriptManager.userScripts.filter(\.isLocal).map(\.name)

        let deletedLocalNamesToClear =
            CloudSyncLocalUserScriptReconciler.deletedNamesToClearDuringUploadReconciliation(
                existingDeletedNames: deletedLocalUserScriptNameSet(),
                localNames: localNames
            )
        if !deletedLocalNamesToClear.isEmpty {
            clearDeletedLocalUserScriptNames(deletedLocalNamesToClear)
        }

        let remoteDeletedLocalNamesToMerge =
            CloudSyncLocalUserScriptReconciler.deletedNamesToMergeDuringUploadReconciliation(
                remoteDeletedNames: remoteDeletedLocalNames,
                localNames: localNames
            )
        if !remoteDeletedLocalNamesToMerge.isEmpty {
            mergeDeletedLocalUserScriptNames(remoteDeletedLocalNamesToMerge)
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
            CloudSyncRemoteUserScriptReconciler.deletedURLsToClearDuringUploadReconciliation(
                existingDeletedURLs: deletedRemoteUserScriptURLSet(),
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
                CloudSyncLocalUserScript(
                    name: $0.name,
                    content: $0.content,
                    isEnabled: $0.isEnabled,
                    updatesAutomatically: $0.updatesAutomatically
                )
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
                    let remoteCategory = remoteCustom.resolvedCategory
                    if let inlineID = Self.inlineUserListID(from: remoteCustom.url) {
                        guard let content = remoteCustom.content else { continue }
                        Self.writeInlineUserListContent(id: inlineID, content: content)
                    }
                    let newFilter = FilterList(
                        id: Self.inlineUserListID(from: remoteCustom.url) ?? UUID(),
                        name: remoteCustom.name,
                        url: URL(string: remoteCustom.url) ?? URL(string: "https://example.com")!,
                        category: remoteCategory,
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
                    let remoteCategory = remoteCustom.resolvedCategory
                    if let inlineID = Self.inlineUserListID(from: remoteCustom.url) {
                        guard let content = remoteCustom.content else { continue }
                        Self.writeInlineUserListContent(id: inlineID, content: content)
                    }
                    let newFilter = FilterList(
                        id: Self.inlineUserListID(from: remoteCustom.url) ?? UUID(),
                        name: remoteCustom.name,
                        url: URL(string: remoteCustom.url) ?? URL(string: "https://example.com")!,
                        category: remoteCategory,
                        isCustom: true,
                        isSelected: remoteCustom.isSelected,
                        description: remoteCustom.description ?? "User-added filter list.",
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
                await userScriptManager.setUserScript(added, updatesAutomatically: remote.resolvedUpdatesAutomatically)
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
                await userScriptManager.setUserScript(imported, updatesAutomatically: local.resolvedUpdatesAutomatically)
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
            filterDisabledDomains: content.filterDisabledDomains,
            zapperRules: content.zapperRules,
            zapperDisabledDomains: content.zapperDisabledDomains
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
                    category: list.category.rawValue,
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

        let userScriptDisabledHosts = dataManager.getUserScriptDisabledHosts()
        let remoteScripts = userScriptManager.userScripts
            .filter { !$0.isLocal && $0.url != nil }
            .compactMap { script -> SyncPayload.RemoteUserScript? in
                guard let url = script.url else { return nil }
                let disabledHosts = Self.normalizedDisabledHosts(
                    userScriptDisabledHosts[script.id.uuidString] ?? [])
                return SyncPayload.RemoteUserScript(
                    url: url.absoluteString,
                    isEnabled: script.isEnabled,
                    updatesAutomatically: script.updatesAutomatically,
                    disabledHosts: disabledHosts
                )
            }
            .sorted { $0.url < $1.url }

        let localScripts = userScriptManager.userScripts
            .filter { $0.isLocal }
            .map { script in
                let disabledHosts = Self.normalizedDisabledHosts(
                    userScriptDisabledHosts[script.id.uuidString] ?? [])
                return SyncPayload.LocalUserScript(
                    name: script.name,
                    content: script.content,
                    isEnabled: script.isEnabled,
                    updatesAutomatically: script.updatesAutomatically,
                    disabledHosts: disabledHosts
                )
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
        let filterDisabledDomains = dataManager.filterDisabledSites.sorted()
        let zapperRules = Self.normalizedZapperRules(
            Dictionary(
                uniqueKeysWithValues: dataManager.getZapperDomains().map { domain in
                    (domain, dataManager.getZapperRules(forHost: domain))
                }
            )
        )
        let zapperDisabledDomains = dataManager.getDisabledZapperDomains()

        return SyncPayload.Content(
            settings: settings,
            filters: filters,
            userScripts: userScripts,
            whitelistDomains: whitelistDomains,
            filterDisabledDomains: filterDisabledDomains,
            zapperRules: zapperRules,
            zapperDisabledDomains: zapperDisabledDomains
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

    private static func normalizedDisabledHosts(_ hosts: [String]) -> [String] {
        Array(Set(hosts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }))
            .sorted()
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

    /// Low-level save with bounded retry for transient errors only (network, quota, etc.).
    /// `.serverRecordChanged` is intentionally re-thrown so the caller can reconcile the
    /// server record's definitions before retrying, rather than silently overwriting it.
    private func saveRecord(_ record: CKRecord, retryCount: Int = 0) async throws -> CKRecord {
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
        } catch let ckError as CKError {
            guard ckError.code != .serverRecordChanged,
                  retryCount < 2,
                  let delay = retryDelay(for: ckError) else {
                throw ckError
            }
            logger.info(
                "CloudKit save failed with retryable error \(ckError.code.rawValue, privacy: .public), retrying in \(String(describing: delay), privacy: .public)"
            )
            try await TaskSleep.sleep(for: delay)
            return try await saveRecord(record, retryCount: retryCount + 1)
        }
    }

    /// Saves the record, resolving `.serverRecordChanged` conflicts by reconciling the
    /// server's definitions into local state and rebuilding the payload before retrying.
    /// Returns the payload that was actually saved, which may differ from the input when a
    /// conflict was merged. Bounding the retries prevents the unbounded recursion that the
    /// old retry-without-increment path could enter. Reconciling before the retry keeps a
    /// concurrently-updated remote record's definitions from being dropped by the
    /// single-payload overwrite.
    private func saveRecordWithConflictResolution(
        _ record: CKRecord,
        payload: SyncPayload,
        maxConflictRetries: Int = 2
    ) async throws -> SyncPayload {
        var tempURLs: [URL] = []
        defer { tempURLs.forEach { try? FileManager.default.removeItem(at: $0) } }

        var currentRecord = record
        var currentPayload = payload
        var conflictRetries = 0

        while true {
            do {
                _ = try await saveRecord(currentRecord)
                return currentPayload
            } catch let ckError as CKError where ckError.code == .serverRecordChanged {
                guard conflictRetries < maxConflictRetries,
                      let serverRecord = ckError.serverRecord else {
                    throw ckError
                }
                conflictRetries += 1
                logger.info("Server record changed; reconciling definitions and retrying save (attempt \(conflictRetries, privacy: .public) of \(maxConflictRetries, privacy: .public))")
                if let serverPayload = try? decodePayload(from: serverRecord) {
                    await reconcileMissingDefinitionsIfNeeded(from: serverPayload)
                }
                currentPayload = buildPayload()
                var mutableRecord = serverRecord
                let payloadURL = try await applyPayloadFields(currentPayload, to: &mutableRecord)
                tempURLs.append(payloadURL)
                currentRecord = mutableRecord
            }
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

    /// Records that local and remote match: stamps lastSyncAt, marks every current local
    /// userscript name as known-synced, and surfaces the up-to-date status.
    private func markUpToDate(from localPayload: SyncPayload) {
        setLastSyncedLocalUserScriptNames(localUserScriptNames(in: localPayload))
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
        refreshStatusFromDefaults()
        setStatus(.upToDate)
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
        static let lastSyncedLocalUserScriptNames = "cloudSyncLastSyncedLocalUserScriptNames"
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
        loadDeletedMarkers(forKey: Keys.deletedCustomURLs)
    }

    private func clearDeletedCustomListURLs(_ urls: Set<String>) {
        guard !urls.isEmpty else { return }
        let normalizedURLs = Set(urls.map(CloudSyncCustomFilterReconciler.normalizedURL).filter { !$0.isEmpty })
        let markers = loadDeletedCustomURLMarkers()
        clearDeletedMarkers(normalizedURLs, markers: markers, saveKey: Keys.deletedCustomURLs)
    }

    private func mergeDeletedCustomListURLs(_ urls: Set<String>) {
        let markers = loadDeletedCustomURLMarkers()
        mergeDeletedMarkers(urls, markers: markers, saveKey: Keys.deletedCustomURLs)
    }

    // MARK: - Deleted Marker Helpers (shared across custom lists, local scripts, remote scripts)

    private func loadDeletedMarkers(forKey key: String) -> [String: TimeInterval] {
        let raw = defaults.dictionary(forKey: key) ?? [:]
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
        let pruned = pruneDeletedMarkers(result)
        if pruned.count != result.count {
            saveDeletedMarkers(pruned, forKey: key)
        }
        return pruned
    }

    private func pruneDeletedMarkers(_ markers: [String: TimeInterval]) -> [String: TimeInterval] {
        let ttl = deletedMarkerTTLDays * 24 * 60 * 60
        let now = Date().timeIntervalSince1970
        return markers.filter { _, deletedAt in
            deletedAt > 0 && (now - deletedAt) <= ttl
        }
    }

    private func saveDeletedMarkers(_ markers: [String: TimeInterval], forKey key: String) {
        let pruned = pruneDeletedMarkers(markers)
        defaults.set(pruned, forKey: key)
    }

    private func mergeDeletedMarkers(_ entries: Set<String>, markers: [String: TimeInterval], saveKey: String) {
        guard !entries.isEmpty else { return }
        var updated = markers
        let now = Date().timeIntervalSince1970
        for entry in entries {
            if !entry.isEmpty, updated[entry] == nil {
                updated[entry] = now
            }
        }
        saveDeletedMarkers(updated, forKey: saveKey)
    }

    private func clearDeletedMarkers(_ entries: Set<String>, markers: [String: TimeInterval], saveKey: String) {
        guard !entries.isEmpty else { return }
        var updated = markers
        var changed = false
        for entry in entries where !entry.isEmpty {
            if updated.removeValue(forKey: entry) != nil {
                changed = true
            }
        }
        if changed {
            saveDeletedMarkers(updated, forKey: saveKey)
        }
    }

    private func localUserScriptNames(in payload: SyncPayload) -> Set<String> {
        Set(
            payload.userScripts.local
                .map { CloudSyncLocalUserScriptReconciler.normalizedName($0.name) }
                .filter { !$0.isEmpty }
        )
    }

    private func lastSyncedLocalUserScriptNameSet() -> Set<String> {
        let raw = defaults.array(forKey: Keys.lastSyncedLocalUserScriptNames) as? [String] ?? []
        return Set(raw.map(CloudSyncLocalUserScriptReconciler.normalizedName).filter { !$0.isEmpty })
    }

    private func setLastSyncedLocalUserScriptNames(_ names: Set<String>) {
        let normalized = Set(
            names.map(CloudSyncLocalUserScriptReconciler.normalizedName).filter { !$0.isEmpty }
        )
        defaults.set(normalized.sorted(), forKey: Keys.lastSyncedLocalUserScriptNames)
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

        let pruned = pruneDeletedMarkers(result)
        if pruned.count != result.count {
            saveDeletedMarkers(pruned, forKey: Keys.deletedLocalUserScriptNames)
        }
        return pruned
    }

    private func saveDeletedLocalUserScriptMarkers(_ markers: [String: TimeInterval]) {
        saveDeletedMarkers(markers, forKey: Keys.deletedLocalUserScriptNames)
    }

    private func mergeDeletedLocalUserScriptNames(_ names: Set<String>) {
        let normalized = Set(names.map(CloudSyncLocalUserScriptReconciler.normalizedName).filter { !$0.isEmpty })
        let markers = loadDeletedLocalUserScriptMarkers()
        mergeDeletedMarkers(normalized, markers: markers, saveKey: Keys.deletedLocalUserScriptNames)
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

        let pruned = pruneDeletedMarkers(result)
        if pruned.count != result.count {
            saveDeletedMarkers(pruned, forKey: Keys.deletedRemoteUserScriptURLs)
        }
        return pruned
    }

    private func pruneDeletedRemoteUserScriptURLMarkers(_ markers: [String: TimeInterval]) -> [String: TimeInterval] {
        pruneDeletedMarkers(markers)
    }

    private func saveDeletedRemoteUserScriptURLMarkers(_ markers: [String: TimeInterval]) {
        saveDeletedMarkers(markers, forKey: Keys.deletedRemoteUserScriptURLs)
    }

    private func clearDeletedRemoteUserScriptURLs(_ urls: Set<String>) {
        guard !urls.isEmpty else { return }
        let normalizedURLs = Set(urls.map(CloudSyncRemoteUserScriptReconciler.normalizedURL).filter { !$0.isEmpty })
        guard !normalizedURLs.isEmpty else { return }
        let markers = loadDeletedRemoteUserScriptURLMarkers()
        clearDeletedMarkers(normalizedURLs, markers: markers, saveKey: Keys.deletedRemoteUserScriptURLs)
    }

    private func mergeDeletedRemoteUserScriptURLs(_ urls: Set<String>) {
        let normalizedURLs = Set(urls.map(CloudSyncRemoteUserScriptReconciler.normalizedURL).filter { !$0.isEmpty })
        let markers = loadDeletedRemoteUserScriptURLMarkers()
        mergeDeletedMarkers(normalizedURLs, markers: markers, saveKey: Keys.deletedRemoteUserScriptURLs)
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
        let category: String?
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
        let updatesAutomatically: Bool?
        let disabledHosts: [String]?

        var resolvedUpdatesAutomatically: Bool {
            updatesAutomatically ?? true
        }
    }

    struct LocalUserScript: Codable {
        let name: String
        let content: String
        let isEnabled: Bool
        let updatesAutomatically: Bool?
        let disabledHosts: [String]?

        var resolvedUpdatesAutomatically: Bool {
            updatesAutomatically ?? true
        }
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
        let filterDisabledDomains: [String]?
        let zapperRules: [String: [String]]?
        let zapperDisabledDomains: [String]?
    }

    let schemaVersion: Int
    let updatedAt: TimeInterval
    let contentHash: String
    let settings: Settings
    let filters: Filters
    let userScripts: UserScripts
    let whitelistDomains: [String]
    let filterDisabledDomains: [String]?
    let zapperRules: [String: [String]]?
    let zapperDisabledDomains: [String]?
}

private extension SyncPayload.CustomFilterList {
    var resolvedCategory: FilterListCategory {
        FilterListCategory(rawValue: category ?? "") ?? .custom
    }
}
