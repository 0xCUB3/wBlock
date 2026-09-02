import CloudKit
import Combine
import CryptoKit
import Foundation
import os.log
import Security
import wBlockCoreService

private enum CloudSyncError: Error {
    case cloudKitUnavailable
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

    @Published private(set) var isCloudKitAvailable: Bool
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
        guard isCloudKitAvailable else {
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
    private var launchSetupWaiters: [CheckedContinuation<Void, Never>] = []
    private var deferredInFlightSyncTrigger: String?
    private var deferredSyncTrigger: String?
    private var hasPendingExplicitRemoteDownload = false
    private var pendingUploadTask: Task<Void, Never>?
    private var pendingSyncTask: Task<Void, Never>?
    private var isApplyingRemoteChanges: Bool = false

    private struct LocalMutationRevisionSnapshot: Equatable {
        let filterSelection: UInt64
        let userScripts: UInt64
    }

    private func localMutationRevisionSnapshot() -> LocalMutationRevisionSnapshot {
        LocalMutationRevisionSnapshot(
            filterSelection: filterManager?.selectionMutationRevision ?? 0,
            userScripts: userScriptManager.localMutationRevision
        )
    }

    private func stableLocalPayloadAndMutationBaseline() async -> (
        payload: SyncPayload, baseline: LocalMutationRevisionSnapshot
    ) {
        while true {
            let baseline = localMutationRevisionSnapshot()
            let payload = await buildPayloadRefreshingSnapshot()
            guard localMutationRevisionSnapshot() == baseline else { continue }
            return (payload, baseline)
        }
    }

    private var uploadCoordinator = CloudSyncUploadCoordinator()
    private let deletedMarkerTTLDays: Double = 90
    /// Minimum interval between automatic (AppActive) syncs. Manual/Launch triggers bypass it.
    private let minimumAutomaticSyncInterval: TimeInterval = 120
    private var lastAutomaticSyncAt: TimeInterval = 0
    private let sortedJSONEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private init() {
        isCloudKitAvailable = Self.hasCloudKitEntitlement
        isEnabled = defaults.bool(forKey: Keys.enabled)
        refreshStatusFromDefaults()
    }

    func activateAfterLaunchSetup() {
        guard !hasActivatedObservers else { return }
        hasActivatedObservers = true
        hasCompletedLaunchSetup = true
        let waiters = launchSetupWaiters
        launchSetupWaiters.removeAll()
        waiters.forEach { $0.resume() }
        observeLocalSaves()
        observeLocalUserScriptChanges()
        observeiCloudAccountChanges()

        let trigger = deferredSyncTrigger
            ?? ((isCloudKitAvailable && isEnabled && !hasPendingExplicitRemoteDownload) ? "Launch" : nil)
        deferredSyncTrigger = nil
        guard let trigger else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncNow(trigger: trigger)
        }
    }

    private func waitUntilLaunchSetupComplete() async {
        if hasCompletedLaunchSetup { return }
        await withCheckedContinuation { continuation in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                if self.hasCompletedLaunchSetup {
                    continuation.resume()
                } else {
                    self.launchSetupWaiters.append(continuation)
                }
            }
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

    func recordDeletedLocalUserScriptName(_ name: String, identity: String? = nil) {
        if let identity = CloudSyncLocalUserScriptReconciler.normalizedIdentity(identity) {
            mergeDeletedMarkers(
                [identity],
                markers: loadDeletedLocalUserScriptIdentityMarkers(),
                saveKey: Keys.deletedLocalUserScriptIdentities
            )
            return
        }
        let normalized = CloudSyncLocalUserScriptReconciler.normalizedName(name)
        guard !normalized.isEmpty else { return }
        mergeDeletedMarkers([normalized], markers: loadDeletedLocalUserScriptMarkers(), saveKey: Keys.deletedLocalUserScriptNames)
    }

    func clearDeletedLocalUserScriptName(_ name: String, identity: String? = nil) {
        if let identity = CloudSyncLocalUserScriptReconciler.normalizedIdentity(identity) {
            clearDeletedMarkers(
                [identity],
                markers: loadDeletedLocalUserScriptIdentityMarkers(),
                saveKey: Keys.deletedLocalUserScriptIdentities
            )
            // Stable identity records do not participate in the legacy name
            // tombstone namespace; clearing by name could affect a duplicate.
            return
        }
        let normalized = CloudSyncLocalUserScriptReconciler.normalizedName(name)
        guard !normalized.isEmpty else { return }
        clearDeletedMarkers([normalized], markers: loadDeletedLocalUserScriptMarkers(), saveKey: Keys.deletedLocalUserScriptNames)
    }

    private func clearDeletedLocalUserScriptNames(_ names: Set<String>) {
        let normalizedNames = Set(names.map(CloudSyncLocalUserScriptReconciler.normalizedName).filter { !$0.isEmpty })
        let markers = loadDeletedLocalUserScriptMarkers()
        clearDeletedMarkers(normalizedNames, markers: markers, saveKey: Keys.deletedLocalUserScriptNames)
    }

    private func clearDeletedLocalUserScriptIdentities(_ identities: Set<String>) {
        let normalized = Set(identities.compactMap(CloudSyncLocalUserScriptReconciler.normalizedIdentity))
        let markers = loadDeletedLocalUserScriptIdentityMarkers()
        clearDeletedMarkers(normalized, markers: markers, saveKey: Keys.deletedLocalUserScriptIdentities)
    }

    func attach(filterManager: AppFilterManager) {
        self.filterManager = filterManager
    }

    func setEnabled(_ enabled: Bool, startSync: Bool = true) {
        guard isCloudKitAvailable else { return }
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

    func syncNow(trigger: String) async {
        guard isCloudKitAvailable else { return }
        guard isEnabled else { return }
        guard hasCompletedLaunchSetup else {
            deferredSyncTrigger = trigger
            return
        }
        // A sync is already in flight: CloudKit calls don't honour task cancellation, so
        // cancelling the running task wouldn't stop it. Remember the latest trigger and run
        // it once the current cycle finishes instead of letting performTwoWaySync's isSyncing
        // guard silently drop it. The AppActive throttle is applied *after* this so a
        // deferred AppActive replay (see finishSyncCycle) isn't prematurely stamped/dropped.
        if isSyncing {
            deferredInFlightSyncTrigger = trigger
            return
        }
        // Automatic AppActive syncs are throttled so rapid foreground transitions
        // (e.g. switching between apps) don't each trigger a full CloudKit fetch.
        if trigger == "AppActive" {
            // systemUptime is monotonic and unaffected by system-clock/NTP changes,
            // unlike Date().timeIntervalSince1970.
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastAutomaticSyncAt >= minimumAutomaticSyncInterval else { return }
            lastAutomaticSyncAt = now
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
        guard isCloudKitAvailable else {
            return RemoteConfigProbe(exists: false, updatedAt: nil, schemaVersion: nil)
        }
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
        guard isCloudKitAvailable else { return false }
        if !hasCompletedLaunchSetup {
            hasPendingExplicitRemoteDownload = true
            defer { hasPendingExplicitRemoteDownload = false }
            await waitUntilLaunchSetupComplete()
        }

        await dataManager.waitUntilLoaded()
        await userScriptManager.waitUntilReady()

        // Capture the actual local payload and revisions before CloudKit suspends us.
        let stableLocal = await stableLocalPayloadAndMutationBaseline()
        let localPayloadBaseline = stableLocal.payload
        let localMutationBaseline = stableLocal.baseline
        do {
            guard let record = try await fetchRecord() else { return false }
            guard let payload = try decodePayload(from: record) else { return false }

            if isSyncing { return false }
            isSyncing = true
            setStatus(.downloading)
            lastErrorMessage = nil
            defer { finishSyncCycle() }

            await applyRemotePayload(
                payload,
                trigger: trigger,
                localPayloadBaseline: localPayloadBaseline,
                localMutationBaseline: localMutationBaseline
            )
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
                    let identity = notification.userInfo?[UserScriptManagerNotificationKey.localImportIdentity] as? String
                    self.clearDeletedLocalUserScriptName(name, identity: identity)
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
                    let identity = notification.userInfo?[UserScriptManagerNotificationKey.localImportIdentity] as? String
                    self.recordDeletedLocalUserScriptName(name, identity: identity)
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

    private func observeiCloudAccountChanges() {
        guard isCloudKitAvailable else { return }
        NotificationCenter.default.publisher(for: .CKAccountChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isEnabled else { return }
                // An account change (sign-in/sign-out/switch) can flip which records are
                // reachable, so bypass the AppActive throttle and reconcile promptly.
                self.lastAutomaticSyncAt = 0
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.syncNow(trigger: "AccountChanged")
                }
            }
            .store(in: &cancellables)
    }

    private func handleLocalSave() {
        guard isCloudKitAvailable else { return }
        guard isEnabled else { return }
        guard !isApplyingRemoteChanges else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.dataManager.waitUntilLoaded()
            await self.userScriptManager.waitUntilReady()
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
        @unknown default:
            logger.error("Unknown CloudSync upload action; deferring upload")
            return
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
        guard isCloudKitAvailable else { return }
        guard isEnabled else { return }

        if !withinSyncSession {
            switch uploadCoordinator.actionForUploadRequest(trigger: trigger, isSyncing: isSyncing) {
            case .deferUntilIdle:
                logger.info("Skipping overlapping upload, queued for later (\(trigger, privacy: .public))")
                return
            case .startNow:
                isSyncing = true
                setStatus(.uploading)
            @unknown default:
                logger.error("Unknown CloudSync upload action; skipping upload")
                return
            }
        }

        defer {
            if !withinSyncSession {
                finishSyncCycle()
            }
        }

        await dataManager.waitUntilLoaded()
        await userScriptManager.waitUntilReady()

        // If local state hasn't changed since the last successful upload, there is nothing
        // to push. Checking before the fetch avoids a CloudKit round trip for the routine
        // save notifications fired by non-sync-visible state (e.g. filter version/count
        // refreshes). Remote-newer changes are still converged by two-way sync.
        let preCheckPayload = await buildPayloadRefreshingSnapshot()
        if preCheckPayload.contentHash == defaults.string(forKey: Keys.lastUploadedHash) {
            markUpToDate(from: preCheckPayload)
            return
        }

        do {
            var record = try await fetchRecord() ?? CKRecord(recordType: recordType, recordID: recordID)

            if let remotePayload = try? decodePayload(from: record) {
                await reconcileMissingDefinitionsIfNeeded(from: remotePayload)
            }

            let payload = await buildPayloadRefreshingSnapshot()

            let payloadURL = try await applyPayloadFields(payload, to: &record)
            defer { try? FileManager.default.removeItem(at: payloadURL) }

            let savedPayload = try await saveRecordWithConflictResolution(record, payload: payload)

            defaults.set(savedPayload.contentHash, forKey: Keys.lastUploadedHash)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastUploadedAt)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
            // The uploaded payload's local script identities/names are now known-synced.
            setLastSyncedLocalUserScriptNames(localUserScriptNames(in: savedPayload))
            setLastSyncedLocalUserScriptIdentities(localUserScriptIdentities(in: savedPayload))
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
        guard isCloudKitAvailable else { return }
        guard isEnabled else { return }
        await dataManager.waitUntilLoaded()
        await userScriptManager.waitUntilReady()

        if isSyncing { return }
        isSyncing = true
        setStatus(.checking)
        lastErrorMessage = nil
        defer { finishSyncCycle() }

        do {
            let stableLocal = await stableLocalPayloadAndMutationBaseline()
            let localPayload = stableLocal.payload
            let localMutationBaseline = stableLocal.baseline
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
                await applyRemotePayload(
                    remotePayload,
                    trigger: trigger,
                    localPayloadBaseline: localPayload,
                    localMutationBaseline: localMutationBaseline
                )
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

    private func applyRemotePayload(
        _ payload: SyncPayload,
        trigger: String,
        localPayloadBaseline: SyncPayload,
        localMutationBaseline: LocalMutationRevisionSnapshot
    ) async {
        logger.info("⬇️ Applying remote payload (\(trigger, privacy: .public))")
        let filterSelectionRevisionAtStart = localMutationBaseline.filterSelection
        let userScriptMutationRevisionAtStart = localMutationBaseline.userScripts
        let settingsBaseline = localPayloadBaseline.settings
        let filtersBaseline = localPayloadBaseline.filters
        let whitelistBaseline = localPayloadBaseline.whitelistDomains
        let filterDisabledBaseline = localPayloadBaseline.filterDisabledDomains
        let noAutoplayEnabledBaseline = localPayloadBaseline.noAutoplayEnabled
        let noAutoplayAllowedBaseline = localPayloadBaseline.noAutoplayAllowedSites
        let zapperBaseline = localPayloadBaseline.zapperRules
        let zapperDisabledBaseline = localPayloadBaseline.zapperDisabledDomains
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        // Merge each settings field independently. Local changes win only their own
        // field; unrelated values from the newer remote payload still apply.
        let currentContent = await buildPayloadContent()
        let currentSettings = currentContent.settings
        if currentSettings.selectedBlockingLevel == settingsBaseline.selectedBlockingLevel {
            await dataManager.setSelectedBlockingLevel(payload.settings.selectedBlockingLevel)
        }
        if currentSettings.isBadgeCounterEnabled == settingsBaseline.isBadgeCounterEnabled {
            await dataManager.setIsBadgeCounterEnabled(payload.settings.isBadgeCounterEnabled)
        }
        var autoUpdateConfigChanged = false
        if currentSettings.autoUpdateEnabled == settingsBaseline.autoUpdateEnabled {
            autoUpdateConfigChanged = currentSettings.autoUpdateEnabled != payload.settings.autoUpdateEnabled
            await dataManager.setAutoUpdateEnabled(payload.settings.autoUpdateEnabled)
        }
        if currentSettings.autoUpdateIntervalHours == settingsBaseline.autoUpdateIntervalHours {
            autoUpdateConfigChanged = autoUpdateConfigChanged
                || currentSettings.autoUpdateIntervalHours != payload.settings.autoUpdateIntervalHours
            await dataManager.setAutoUpdateIntervalHours(payload.settings.autoUpdateIntervalHours)
        }
        if autoUpdateConfigChanged {
            await SharedAutoUpdateManager.shared.resetScheduleAfterConfigurationChange()
        }
        if currentSettings.userScriptShowEnabledOnly == settingsBaseline.userScriptShowEnabledOnly {
            dataManager.setUserScriptShowEnabledOnly(payload.settings.userScriptShowEnabledOnly)
        }
        let mergedExcluded = Self.mergeStringSet(
            local: currentSettings.excludedDefaultUserScriptURLs,
            baseline: settingsBaseline.excludedDefaultUserScriptURLs,
            remote: payload.settings.excludedDefaultUserScriptURLs
        )
        let currentExcluded = Set(dataManager.getExcludedDefaultUserScriptURLs())
        let desiredExcluded = Set(mergedExcluded)
        for url in desiredExcluded.subtracting(currentExcluded) {
            dataManager.addExcludedDefaultUserScriptURL(url)
        }
        for url in currentExcluded.subtracting(desiredExcluded) {
            dataManager.removeExcludedDefaultUserScriptURL(url)
        }

        // Merge domain sets independently so a local whitelist edit does not discard a
        // simultaneous remote filter-only exception (or vice versa).
        await dataManager.setWhitelistedDomains(Self.mergeStringSet(
            local: currentContent.whitelistDomains,
            baseline: whitelistBaseline,
            remote: payload.whitelistDomains
        ))
        // A 2.2.0 payload omits these 3.0.0-only keys. Nil means no remote opinion:
        // keep local. A present empty collection still means remote cleared the set.
        if let remoteFilterDisabledDomains = payload.filterDisabledDomains {
            await dataManager.setFilterDisabledDomains(Self.mergeStringSet(
                local: currentContent.filterDisabledDomains ?? [],
                baseline: filterDisabledBaseline ?? [],
                remote: remoteFilterDisabledDomains
            ))
        }

        let currentNoAutoplayEnabled = currentContent.noAutoplayEnabled ?? false
        let baselineNoAutoplayEnabled = noAutoplayEnabledBaseline ?? false
        if currentNoAutoplayEnabled == baselineNoAutoplayEnabled,
           let remoteNoAutoplayEnabled = payload.noAutoplayEnabled
        {
            await dataManager.setNoAutoplayEnabled(remoteNoAutoplayEnabled)
        }
        if let remoteNoAutoplayAllowedSites = payload.noAutoplayAllowedSites {
            await dataManager.setNoAutoplayAllowedSites(Self.mergeStringSet(
                local: currentContent.noAutoplayAllowedSites ?? [],
                baseline: noAutoplayAllowedBaseline ?? [],
                remote: remoteNoAutoplayAllowedSites
            ))
        }

        // Merge zapper hosts per key and disabled-host choices as a set.
        let mergedZapperRules: [String: [String]]
        if let remoteZapperRules = payload.zapperRules {
            mergedZapperRules = Self.mergeDictionary(
                local: currentContent.zapperRules ?? [:],
                baseline: zapperBaseline ?? [:],
                remote: remoteZapperRules
            )
        } else {
            mergedZapperRules = currentContent.zapperRules ?? [:]
        }
        let mergedZapperDisabled: [String]
        if let remoteZapperDisabledDomains = payload.zapperDisabledDomains {
            mergedZapperDisabled = Self.mergeStringSet(
                local: currentContent.zapperDisabledDomains ?? [],
                baseline: zapperDisabledBaseline ?? [],
                remote: remoteZapperDisabledDomains
            )
        } else {
            mergedZapperDisabled = currentContent.zapperDisabledDomains ?? []
        }
        await applyRemoteZapperRules(mergedZapperRules, disabledDomains: mergedZapperDisabled)

        await applyRemoteFilters(
            payload.filters,
            baselineFilters: filtersBaseline,
            localSelectionRevisionAtStart: filterSelectionRevisionAtStart
        )

        // User scripts (remote URLs + local imports)
        let keptUnsyncedLocalScripts = await applyRemoteUserScripts(
            payload.userScripts,
            localMutationRevisionAtStart: userScriptMutationRevisionAtStart
        )

        if let filterManager,
           filterManager.selectionMutationRevision != filterSelectionRevisionAtStart
        {
            await filterManager.saveFilterLists()
        }

        // Rebuild blockers so the synced config takes effect. A local toggle can happen
        // during this await, so hash finalization is deliberately after the rebuild.
        if let filterManager {
            await filterManager.applyChanges(allowUserInteraction: true)
        }

        let localMutationDuringApply =
            (filterManager?.selectionMutationRevision ?? filterSelectionRevisionAtStart)
                != filterSelectionRevisionAtStart
            || userScriptManager.localMutationRevision != userScriptMutationRevisionAtStart

        let finalLocalPayload = await buildPayloadRefreshingSnapshot()
        let localPayloadDiffersFromRemote = finalLocalPayload.contentHash != payload.contentHash

        // Only a fully converged apply can advance the known-synced script baseline.
        if !localMutationDuringApply && !localPayloadDiffersFromRemote {
            setLastSyncedLocalUserScriptNames(localUserScriptNames(in: payload))
            setLastSyncedLocalUserScriptIdentities(localUserScriptIdentities(in: payload))
        }

        // A local edit or a guarded section means the remote hash is not current locally.
        if !localMutationDuringApply && !localPayloadDiffersFromRemote {
            defaults.set(payload.contentHash, forKey: Keys.lastLocalHash)
            defaults.set(payload.updatedAt, forKey: Keys.lastLocalUpdatedAt)
            defaults.set(payload.contentHash, forKey: Keys.lastDownloadedHash)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastDownloadedAt)
            defaults.set(payload.contentHash, forKey: Keys.lastUploadedHash)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
            refreshStatusFromDefaults()
        }

        // A local userscript that was never synced, or a local toggle made during apply, needs
        // a follow-up upload after the current sync becomes idle.
        if keptUnsyncedLocalScripts {
            scheduleUpload(trigger: "\(trigger)-KeepUnsyncedLocal")
        }
        if (localMutationDuringApply || localPayloadDiffersFromRemote) && !keptUnsyncedLocalScripts {
            scheduleUpload(trigger: "\(trigger)-LocalMutationDuringApply")
        }
    }

    private func encodedSectionEqual<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool {
        guard let left = try? sortedJSONEncoder.encode(lhs),
              let right = try? sortedJSONEncoder.encode(rhs)
        else { return false }
        return left == right
    }

    private static func mergeStringSet(
        local: [String],
        baseline: [String],
        remote: [String]
    ) -> [String] {
        let baselineSet = Set(baseline)
        let localSet = Set(local)
        var merged = Set(remote)
        merged.subtract(baselineSet.subtracting(localSet))
        merged.formUnion(localSet.subtracting(baselineSet))
        return merged.sorted()
    }

    private static func mergeDictionary<Key: Hashable, Value: Equatable>(
        local: [Key: Value],
        baseline: [Key: Value],
        remote: [Key: Value]
    ) -> [Key: Value] {
        var merged = remote
        let keys = Set(baseline.keys).union(local.keys)
        for key in keys where local[key] != baseline[key] {
            merged[key] = local[key]
        }
        return merged
    }

    private func applyRemoteFilters(
        _ filters: SyncPayload.Filters,
        baselineFilters: SyncPayload.Filters,
        localSelectionRevisionAtStart: UInt64
    ) async {
        let currentFilters = (await buildPayloadContent()).filters
        let baselineCustomByURL = Dictionary(
            baselineFilters.customLists.map { ($0.url, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let currentCustomByURL = Dictionary(
            currentFilters.customLists.map { ($0.url, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let customURLs = Set(baselineCustomByURL.keys).union(currentCustomByURL.keys)
        let locallyChangedCustomURLs = Set(customURLs.filter { url in
            !encodedSectionEqual(currentCustomByURL[url], baselineCustomByURL[url])
        })

        // Tombstones are a set-valued field: merge local and remote deltas instead of
        // replacing one side wholesale.
        let currentDeleted = Set(currentFilters.deletedCustomURLs ?? [])
        var mergedDeleted = Set(Self.mergeStringSet(
            local: Array(currentDeleted),
            baseline: baselineFilters.deletedCustomURLs ?? [],
            remote: filters.deletedCustomURLs ?? []
        ))
        for url in locallyChangedCustomURLs where currentCustomByURL[url] != nil {
            // A local add/edit wins a conflicting remote tombstone for that URL.
            mergedDeleted.remove(url)
        }
        clearDeletedCustomListURLs(currentDeleted.subtracting(mergedDeleted))
        mergeDeletedCustomListURLs(mergedDeleted.subtracting(currentDeleted))
        let deletedCustomURLs = mergedDeleted

        let desiredSelected = Set(
            filters.selectedURLs.map(FilterListLoader.canonicalFilterURLString)
        )
        let knownURLs = Set(
            (filters.knownURLs ?? filters.selectedURLs).map(FilterListLoader.canonicalFilterURLString)
        )

        if let filterManager {
            var changed = false
            var selectionChanged = false
            var nonSelectionChanged = false
            let mayApplyRemoteSelection =
                filterManager.selectionMutationRevision == localSelectionRevisionAtStart

            // Remove remotely deleted custom lists only when that URL was unchanged locally.
            if !deletedCustomURLs.isEmpty {
                let liveCustomURLs = Set(
                    filterManager.filterLists.filter(\.isCustom).map(\.url.absoluteString)
                )
                let urlsToDelete = CloudSyncCustomFilterReconciler.tombstonedURLsToDelete(
                    tombstonedURLs: deletedCustomURLs.subtracting(locallyChangedCustomURLs),
                    snapshotCustomURLs: Set(currentCustomByURL.keys),
                    liveCustomURLs: liveCustomURLs
                )
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
                let urlString = FilterListLoader.canonicalFilterURLString(
                    filterManager.filterLists[index].url.absoluteString
                )
                guard knownURLs.contains(urlString), mayApplyRemoteSelection else { continue }
                let shouldSelect = desiredSelected.contains(urlString)
                if filterManager.filterLists[index].isSelected != shouldSelect {
                    filterManager.filterLists[index].isSelected = shouldSelect
                    changed = true
                    selectionChanged = true
                }
            }

            // Upsert remote custom lists independently by URL.
            for remoteCustom in filters.customLists {
                if locallyChangedCustomURLs.contains(remoteCustom.url) {
                    continue
                }
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
                        if mayApplyRemoteSelection,
                           filterManager.filterLists[existingIndex].isSelected != remoteCustom.isSelected
                        {
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
                            isSelected: mayApplyRemoteSelection ? remoteCustom.isSelected : false,
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
                        isSelected: mayApplyRemoteSelection ? remoteCustom.isSelected : false,
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
            let urlsToDelete = deletedCustomURLs.subtracting(locallyChangedCustomURLs)
            storedLists.removeAll { $0.isCustom && urlsToDelete.contains($0.url.absoluteString) }
            for url in urlsToDelete {
                Self.deleteInlineUserListContentIfNeeded(urlString: url)
            }
        }

        let mayApplyRemoteSelection =
            filterManager == nil
                || filterManager?.selectionMutationRevision == localSelectionRevisionAtStart
        for index in storedLists.indices where !storedLists[index].isCustom {
            let urlString = FilterListLoader.canonicalFilterURLString(
                storedLists[index].url.absoluteString
            )
            guard knownURLs.contains(urlString), mayApplyRemoteSelection else { continue }
            storedLists[index].isSelected = desiredSelected.contains(urlString)
        }

        // Upsert custom lists from remote without removing local-only customs.
        let localCustomIndexByURL: [String: Int] = Dictionary(
            uniqueKeysWithValues: storedLists.indices.compactMap { idx in
                guard storedLists[idx].isCustom else { return nil }
                return (storedLists[idx].url.absoluteString, idx)
            }
        )

        for remoteCustom in filters.customLists
            where !deletedCustomURLs.contains(remoteCustom.url)
                && !locallyChangedCustomURLs.contains(remoteCustom.url)
        {
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
                if mayApplyRemoteSelection {
                    updated.isSelected = remoteCustom.isSelected
                }
                storedLists[existingIndex] = updated
            } else {
                let newFilter = FilterList(
                    id: Self.inlineUserListID(from: remoteCustom.url) ?? UUID(),
                    name: remoteCustom.name,
                    url: URL(string: remoteCustom.url) ?? URL(string: "https://example.com")!,
                    category: remoteCategory,
                    isCustom: true,
                    isSelected: mayApplyRemoteSelection ? remoteCustom.isSelected : false,
                    description: remoteCustom.description ?? "User-added filter list.",
                    sourceRuleCount: nil
                )
                storedLists.append(newFilter)
            }
        }

        await dataManager.updateFilterLists(storedLists)
    }

    private func applyRemoteUserScriptEnabledState(
        _ script: UserScript,
        isEnabled: Bool,
        localMutationRevisionAtStart: UInt64
    ) async {
        guard userScriptManager.localMutationRevision == localMutationRevisionAtStart else { return }
        await userScriptManager.setUserScript(
            script,
            isEnabled: isEnabled,
            origin: .remoteSync
        )
    }

    @discardableResult
    private func applyRemoteUserScripts(
        _ scripts: SyncPayload.UserScripts,
        localMutationRevisionAtStart: UInt64
    ) async -> Bool {
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
                guard userScriptManager.localMutationRevision == localMutationRevisionAtStart else { continue }
                await userScriptManager.removeUserScript(script, origin: .remoteSync)
            }
        }

        let remoteDeletedLocalNames = Set(scripts.deletedLocalNames ?? [])
        let remoteDeletedLocalIdentities = Set(scripts.deletedLocalIdentities ?? [])
        let currentLocalScripts = await userScriptManager.cloudSyncLocalUserScripts()
        let localNames = currentLocalScripts.map(\.name)
        let currentLocalModels = currentLocalScripts.map {
            CloudSyncLocalUserScript(
                name: $0.name,
                content: $0.content,
                isEnabled: $0.isEnabled,
                description: $0.description,
                localImportIdentity: $0.localImportIdentity
            )
        }
        let remoteLocalScripts = scripts.local.map {
            CloudSyncLocalUserScript(
                name: $0.name,
                content: $0.content,
                isEnabled: $0.isEnabled,
                description: $0.description,
                updatesAutomatically: $0.updatesAutomatically,
                category: $0.category,
                localImportIdentity: $0.localImportIdentity
            )
        }

        let deletedLocalNamesToClear =
            CloudSyncLocalUserScriptReconciler.deletedNamesToClearDuringReconciliation(
                existingDeletedNames: deletedLocalUserScriptNameSet(),
                remoteLocalScripts: remoteLocalScripts,
                localNames: localNames,
                remoteDeletedNames: remoteDeletedLocalNames
            )
        if !deletedLocalNamesToClear.isEmpty {
            clearDeletedLocalUserScriptNames(deletedLocalNamesToClear)
        }

        let deletedLocalIdentitiesToClear =
            CloudSyncLocalUserScriptReconciler.deletedIdentitiesToClearDuringReconciliation(
                existingDeletedIdentities: deletedLocalUserScriptIdentitySet(),
                remoteLocalScripts: remoteLocalScripts,
                localScripts: currentLocalModels,
                remoteDeletedIdentities: remoteDeletedLocalIdentities
            )
        if !deletedLocalIdentitiesToClear.isEmpty {
            clearDeletedLocalUserScriptIdentities(deletedLocalIdentitiesToClear)
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

        let remoteDeletedLocalIdentitiesToMerge =
            CloudSyncLocalUserScriptReconciler.deletedIdentitiesToMergeDuringRemoteApply(
                remoteDeletedIdentities: remoteDeletedLocalIdentities,
                remoteLocalScripts: remoteLocalScripts,
                localScripts: currentLocalModels
            )
        if !remoteDeletedLocalIdentitiesToMerge.isEmpty {
            mergeDeletedLocalUserScriptIdentities(remoteDeletedLocalIdentitiesToMerge)
        }

        // Remote scripts (URL-based): ensure each desired script exists, then set its
        // enabled / auto-update state. Downloads for missing scripts run concurrently so a
        // multi-script restore isn't serialized behind each network fetch; the cheap local
        // state writes are applied afterwards to keep them sequential.
        let desiredRemoteScripts = scripts.remote.filter { remote in
            let normalizedURL = CloudSyncRemoteUserScriptReconciler.normalizedURL(remote.url)
            guard !normalizedURL.isEmpty, !deletedRemoteURLs.contains(normalizedURL) else {
                return false
            }
            return CloudSyncRemoteUserScriptReconciler.canonicalURL(remote.url) != nil
        }

        for remote in desiredRemoteScripts {
            guard let url = CloudSyncRemoteUserScriptReconciler.canonicalURL(remote.url) else { continue }
            if let existing = userScriptManager.userScripts.first(where: { $0.url == url }) {
                await applyRemoteUserScriptEnabledState(
                    existing,
                    isEnabled: remote.isEnabled,
                    localMutationRevisionAtStart: localMutationRevisionAtStart
                )
                await userScriptManager.setUserScript(existing, updatesAutomatically: remote.resolvedUpdatesAutomatically, origin: .remoteSync)
                if let category = remote.category,
                   let resolvedCategory = FilterListCategory(rawValue: category) {
                    await userScriptManager.setUserScript(existing, category: resolvedCategory, origin: .remoteSync)
                }
            }
        }

        let missingRemoteScripts = desiredRemoteScripts.filter { remote in
            guard let url = CloudSyncRemoteUserScriptReconciler.canonicalURL(remote.url) else { return false }
            return userScriptManager.userScripts.first(where: { $0.url == url }) == nil
        }

        if !missingRemoteScripts.isEmpty {
            let manager = userScriptManager
            await boundedConcurrentForEach(missingRemoteScripts, operation: { remote in
                guard await manager.currentLocalSyncMutationRevision() == localMutationRevisionAtStart else { return }
                guard let url = CloudSyncRemoteUserScriptReconciler.canonicalURL(remote.url) else { return }
                await manager.addUserScript(from: url, origin: .remoteSync)
            }, onResult: { _ in })

            for remote in missingRemoteScripts {
                guard let url = CloudSyncRemoteUserScriptReconciler.canonicalURL(remote.url) else { continue }
                if let added = userScriptManager.userScripts.first(where: { $0.url == url }) {
                    await applyRemoteUserScriptEnabledState(
                        added,
                        isEnabled: remote.isEnabled,
                        localMutationRevisionAtStart: localMutationRevisionAtStart
                    )
                    await userScriptManager.setUserScript(added, updatesAutomatically: remote.resolvedUpdatesAutomatically, origin: .remoteSync)
                    if let category = remote.category,
                       let resolvedCategory = FilterListCategory(rawValue: category) {
                        await userScriptManager.setUserScript(added, category: resolvedCategory, origin: .remoteSync)
                    }
                }
            }
        }

        // Local scripts (content-based)
        // The newer remote payload is authoritative for synced local imports.

        let deletedLocalNames = deletedLocalUserScriptNameSet()
        let deletedLocalIdentities = deletedLocalUserScriptIdentitySet()
        let lastSyncedNames = lastSyncedLocalUserScriptNameSet()
        let lastSyncedIdentities = lastSyncedLocalUserScriptIdentitySet()
        let localScriptsToDelete = CloudSyncLocalUserScriptReconciler.localScriptsToDeleteDuringRemoteApply(
            localScripts: currentLocalScripts.map {
                CloudSyncLocalUserScript(
                    name: $0.name,
                    content: $0.content,
                    isEnabled: $0.isEnabled,
                    description: $0.description,
                    localImportIdentity: $0.localImportIdentity
                )
            },
            remoteScripts: remoteLocalScripts,
            deletedNames: deletedLocalNames,
            lastSyncedNames: lastSyncedNames,
            deletedIdentities: deletedLocalIdentities,
            lastSyncedIdentities: lastSyncedIdentities
        )
        let keptUnsyncedLocalScripts = CloudSyncLocalUserScriptReconciler.localScriptsNeverSyncedToUpload(
            localScripts: currentLocalModels,
            remoteScripts: remoteLocalScripts,
            deletedNames: deletedLocalNames,
            deletedIdentities: deletedLocalIdentities,
            lastSyncedNames: lastSyncedNames,
            lastSyncedIdentities: lastSyncedIdentities
        )

        if !localScriptsToDelete.isEmpty {
            let scriptsToDelete = currentLocalScripts.filter { script in
                let identity = CloudSyncLocalUserScriptReconciler.normalizedIdentity(script.localImportIdentity)
                return localScriptsToDelete.contains(
                    identity ?? CloudSyncLocalUserScriptReconciler.normalizedName(script.name))
            }
            for script in scriptsToDelete {
                guard userScriptManager.localMutationRevision == localMutationRevisionAtStart else { continue }
                await userScriptManager.removeUserScript(script, origin: .remoteSync)
            }
        }

        // A stale payload can contain a record that is also tombstoned locally.
        // Keep it out of every restore/update pass, not just the missing-item pass.
        let restorableRemoteLocalScripts = CloudSyncLocalUserScriptReconciler.remoteScriptsAllowedAfterTombstones(
            remoteLocalScripts,
            deletedNames: deletedLocalNames,
            deletedIdentities: deletedLocalIdentities
        )
        for local in restorableRemoteLocalScripts {
            guard userScriptManager.localMutationRevision == localMutationRevisionAtStart else { continue }
            let existing = userScriptManager.userScripts.first(where: {
                CloudSyncLocalUserScriptReconciler.matches(existing: $0, remote: local)
            })
            if let existing, existing.content == local.content {
                await applyRemoteUserScriptEnabledState(
                    existing,
                    isEnabled: local.isEnabled,
                    localMutationRevisionAtStart: localMutationRevisionAtStart
                )
                await userScriptManager.setUserScript(existing, updatesAutomatically: local.resolvedUpdatesAutomatically, origin: .remoteSync)
                if let description = local.description {
                    _ = await userScriptManager.setUserScriptMetadataOverrides(
                        for: existing.id,
                        name: existing.name,
                        description: description,
                        origin: .remoteSync
                    )
                }
                if let category = local.category,
                   let resolvedCategory = FilterListCategory(rawValue: category) {
                    await userScriptManager.setUserScript(existing, category: resolvedCategory, origin: .remoteSync)
                }
                continue
            }

            guard userScriptManager.localMutationRevision == localMutationRevisionAtStart else { continue }
            _ = await userScriptManager.addUserScript(
                fromSourceContent: local.content,
                nameOverride: local.name,
                descriptionOverride: local.description ?? existing?.description,
                category: local.category.flatMap(FilterListCategory.init(rawValue:)),
                localImportIdentity: local.localImportIdentity,
                legacyLocalImportMatching: local.localImportIdentity == nil,
                origin: .remoteSync
            )

            if let imported = userScriptManager.userScripts.first(where: {
                CloudSyncLocalUserScriptReconciler.matches(existing: $0, remote: local)
            }) {
                await applyRemoteUserScriptEnabledState(
                    imported,
                    isEnabled: local.isEnabled,
                    localMutationRevisionAtStart: localMutationRevisionAtStart
                )
                await userScriptManager.setUserScript(imported, updatesAutomatically: local.resolvedUpdatesAutomatically, origin: .remoteSync)
                if let category = local.category,
                   let resolvedCategory = FilterListCategory(rawValue: category) {
                    await userScriptManager.setUserScript(imported, category: resolvedCategory, origin: .remoteSync)
                }
            }
        }

        var disabledHostsByScriptID = dataManager.getUserScriptDisabledHosts()
        for remote in scripts.remote {
            guard let disabledHosts = remote.disabledHosts else { continue }
            guard let url = CloudSyncRemoteUserScriptReconciler.canonicalURL(remote.url) else { continue }
            guard let script = userScriptManager.userScripts.first(where: { $0.url == url }) else { continue }
            disabledHostsByScriptID[script.id.uuidString] = disabledHosts
        }

        for local in scripts.local {
            guard let disabledHosts = local.disabledHosts else { continue }
            let localModel = CloudSyncLocalUserScript(
                name: local.name,
                content: local.content,
                isEnabled: local.isEnabled,
                description: local.description,
                updatesAutomatically: local.updatesAutomatically,
                category: local.category,
                localImportIdentity: local.localImportIdentity
            )
            guard restorableRemoteLocalScripts.contains(where: {
                CloudSyncLocalUserScriptReconciler.matches(existing: localModel, remote: $0)
            }),
            let script = userScriptManager.userScripts.first(where: {
                CloudSyncLocalUserScriptReconciler.matches(existing: $0, remote: localModel)
            }) else {
                continue
            }
            disabledHostsByScriptID[script.id.uuidString] = disabledHosts
        }
        await dataManager.setAllUserScriptDisabledHosts(disabledHostsByScriptID)

        // Report whether any never-synced local scripts were kept so the caller can schedule an
        // upload to propagate them to the cloud (#437).
        return !keptUnsyncedLocalScripts.isEmpty
    }

    private func applyRemoteZapperRules(_ zapperRules: [String: [String]], disabledDomains: [String]?) async {
        let normalizedRemoteRules = Self.normalizedZapperRules(zapperRules)
        let currentDomains = Set(dataManager.getZapperDomains())
        let remoteDomains = Set(normalizedRemoteRules.keys)

        var disabledByHost: [String: Bool]? = nil
        if let disabledDomains {
            let disabledDomainSet = Set(Self.normalizedDisabledHosts(disabledDomains))
            disabledByHost = Dictionary(
                uniqueKeysWithValues: normalizedRemoteRules.keys.map { ($0, disabledDomainSet.contains($0)) }
            )
        }
        await dataManager.applyZapperRulesBatch(
            hostsToDelete: currentDomains.subtracting(remoteDomains).sorted(),
            rulesByHost: normalizedRemoteRules,
            disabledByHost: disabledByHost
        )

        await ZapperRuleManager.shared.refreshNow()
    }

    private func reconcileMissingDefinitionsIfNeeded(from remotePayload: SyncPayload) async {
        // Import missing custom filter lists and userscripts before uploading so we don't
        // accidentally drop them from the single shared CloudKit payload.
        let filterSelectionRevisionAtStart = filterManager?.selectionMutationRevision ?? 0

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
        let remoteDeletedLocalIdentities = Set(remotePayload.userScripts.deletedLocalIdentities ?? [])
        let localScripts = (await userScriptManager.cloudSyncLocalUserScripts()).map {
            CloudSyncLocalUserScript(
                name: $0.name,
                content: $0.content,
                isEnabled: $0.isEnabled,
                description: $0.description,
                localImportIdentity: $0.localImportIdentity
            )
        }
        let localNames = localScripts.map(\.name)

        let deletedLocalNamesToClear =
            CloudSyncLocalUserScriptReconciler.deletedNamesToClearDuringUploadReconciliation(
                existingDeletedNames: deletedLocalUserScriptNameSet(),
                localNames: localNames
            )
        if !deletedLocalNamesToClear.isEmpty {
            clearDeletedLocalUserScriptNames(deletedLocalNamesToClear)
        }

        let deletedLocalIdentitiesToClear =
            CloudSyncLocalUserScriptReconciler.deletedIdentitiesToClearDuringUploadReconciliation(
                existingDeletedIdentities: deletedLocalUserScriptIdentitySet(),
                localScripts: localScripts
            )
        if !deletedLocalIdentitiesToClear.isEmpty {
            clearDeletedLocalUserScriptIdentities(deletedLocalIdentitiesToClear)
        }

        let remoteDeletedLocalNamesToMerge =
            CloudSyncLocalUserScriptReconciler.deletedNamesToMergeDuringUploadReconciliation(
                remoteDeletedNames: remoteDeletedLocalNames,
                localNames: localNames
            )
        if !remoteDeletedLocalNamesToMerge.isEmpty {
            mergeDeletedLocalUserScriptNames(remoteDeletedLocalNamesToMerge)
        }

        let remoteDeletedLocalIdentitiesToMerge =
            CloudSyncLocalUserScriptReconciler.deletedIdentitiesToMergeDuringUploadReconciliation(
                remoteDeletedIdentities: remoteDeletedLocalIdentities,
                localScripts: localScripts
            )
        if !remoteDeletedLocalIdentitiesToMerge.isEmpty {
            mergeDeletedLocalUserScriptIdentities(remoteDeletedLocalIdentitiesToMerge)
        }

        let deletedCustomURLs = deletedCustomURLSet()
        if !deletedCustomURLs.isEmpty {
            if let filterManager {
                let urlsToDelete = CloudSyncCustomFilterReconciler.tombstonedURLsToDelete(
                    tombstonedURLs: deletedCustomURLs,
                    snapshotCustomURLs: localCustomURLs,
                    liveCustomURLs: currentLocalCustomURLs()
                )
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
                let liveCustomURLs = Set(storedLists.filter(\.isCustom).map(\.url.absoluteString))
                let urlsToDelete = CloudSyncCustomFilterReconciler.tombstonedURLsToDelete(
                    tombstonedURLs: deletedCustomURLs,
                    snapshotCustomURLs: localCustomURLs,
                    liveCustomURLs: liveCustomURLs
                )
                let beforeCount = storedLists.count
                storedLists.removeAll { $0.isCustom && urlsToDelete.contains($0.url.absoluteString) }
                if storedLists.count != beforeCount {
                    for url in urlsToDelete {
                        Self.deleteInlineUserListContentIfNeeded(urlString: url)
                    }
                    await dataManager.updateFilterLists(storedLists)
                }
            }
        }

        let deletedLocalNames = deletedLocalUserScriptNameSet()
        let deletedLocalIdentities = deletedLocalUserScriptIdentitySet()
        if !deletedLocalNames.isEmpty || !deletedLocalIdentities.isEmpty {
            let scriptsToDelete = userScriptManager.userScripts.filter { script in
                guard script.isLocal else { return false }
                if let identity = CloudSyncLocalUserScriptReconciler.normalizedIdentity(script.localImportIdentity) {
                    return deletedLocalIdentities.contains(identity)
                }
                return deletedLocalNames.contains(
                    CloudSyncLocalUserScriptReconciler.normalizedName(script.name))
            }
            for script in scriptsToDelete {
                await userScriptManager.removeUserScript(script, origin: .remoteSync)
            }
        }

        let remoteCustoms = remotePayload.filters.customLists
        let missingCustoms = remoteCustoms.filter {
            !deletedCustomURLs.contains($0.url) && !localCustomURLs.contains($0.url)
        }

        let localRemoteScriptURLs = currentLocalRemoteUserScriptURLs()
        let remoteRemoteScripts = remotePayload.userScripts.remote
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
                await userScriptManager.removeUserScript(script, origin: .remoteSync)
            }
        }

        let missingRemoteScripts = remoteRemoteScripts.filter { remote in
            let normalizedURL = CloudSyncRemoteUserScriptReconciler.normalizedURL(remote.url)
            return !normalizedURL.isEmpty
                && !deletedRemoteURLs.contains(normalizedURL)
                && !localRemoteScriptURLs.contains(normalizedURL)
        }

        let remoteLocalScripts = remotePayload.userScripts.local.map {
            CloudSyncLocalUserScript(
                name: $0.name,
                content: $0.content,
                isEnabled: $0.isEnabled,
                description: $0.description,
                updatesAutomatically: $0.updatesAutomatically,
                category: $0.category,
                localImportIdentity: $0.localImportIdentity
            )
        }
        let currentLocalScripts = (await userScriptManager.cloudSyncLocalUserScripts()).map {
            CloudSyncLocalUserScript(
                name: $0.name,
                content: $0.content,
                isEnabled: $0.isEnabled,
                description: $0.description,
                localImportIdentity: $0.localImportIdentity
            )
        }
        let missingLocalScripts = CloudSyncLocalUserScriptReconciler.missingRemoteScriptsToRestore(
            remoteScripts: remoteLocalScripts,
            localScripts: currentLocalScripts,
            deletedNames: deletedLocalNames,
            deletedIdentities: deletedLocalIdentities
        )

        guard !missingCustoms.isEmpty || !missingRemoteScripts.isEmpty || !missingLocalScripts.isEmpty else {
            return
        }

        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        if !missingCustoms.isEmpty {
            let mayApplyRemoteSelection =
                (filterManager?.selectionMutationRevision ?? filterSelectionRevisionAtStart)
                    == filterSelectionRevisionAtStart
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
                        isSelected: mayApplyRemoteSelection ? remoteCustom.isSelected : false,
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
                        isSelected: mayApplyRemoteSelection ? remoteCustom.isSelected : false,
                        description: remoteCustom.description ?? "User-added filter list.",
                        sourceRuleCount: nil
                    )
                    storedLists.append(newFilter)
                }
                await dataManager.updateFilterLists(storedLists)
            }
        }

        if !missingRemoteScripts.isEmpty {
            let manager = userScriptManager
            await boundedConcurrentForEach(missingRemoteScripts, operation: { remote in

                guard let url = CloudSyncRemoteUserScriptReconciler.canonicalURL(remote.url) else { return }
                await manager.addUserScript(from: url, origin: .remoteSync)
            }, onResult: { _ in })

            for remote in missingRemoteScripts {
                guard let url = CloudSyncRemoteUserScriptReconciler.canonicalURL(remote.url) else { continue }
                if let added = userScriptManager.userScripts.first(where: { $0.url == url }) {
                    await userScriptManager.setUserScript(
                        added,
                        isEnabled: remote.isEnabled,
                        origin: .remoteSync
                    )
                    await userScriptManager.setUserScript(added, updatesAutomatically: remote.resolvedUpdatesAutomatically, origin: .remoteSync)
                    if let category = remote.category,
                       let resolvedCategory = FilterListCategory(rawValue: category) {
                        await userScriptManager.setUserScript(added, category: resolvedCategory, origin: .remoteSync)
                    }
                }
            }
        }

        for local in missingLocalScripts {

            _ = await userScriptManager.addUserScript(
                fromSourceContent: local.content,
                nameOverride: local.name,
                descriptionOverride: local.description,
                category: local.category.flatMap(FilterListCategory.init(rawValue:)),
                localImportIdentity: local.localImportIdentity,
                legacyLocalImportMatching: local.localImportIdentity == nil,
                origin: .remoteSync
            )
            if let imported = userScriptManager.userScripts.first(where: {
                CloudSyncLocalUserScriptReconciler.matches(existing: $0, remote: local)
            }) {
                await userScriptManager.setUserScript(
                    imported,
                    isEnabled: local.isEnabled,
                    origin: .remoteSync
                )
                await userScriptManager.setUserScript(imported, updatesAutomatically: local.resolvedUpdatesAutomatically, origin: .remoteSync)
                if let category = local.category,
                   let resolvedCategory = FilterListCategory(rawValue: category) {
                    await userScriptManager.setUserScript(imported, category: resolvedCategory, origin: .remoteSync)
                }
            }
        }

        // The local snapshot (lastLocalHash/lastLocalUpdatedAt) is refreshed by the caller
        // when it rebuilds the payload via buildPayloadRefreshingSnapshot after reconcile.
    }

    // MARK: - Payload construction

    /// Builds the payload while refreshing the persisted local content-hash/timestamp
    /// snapshot in one pass. This replaces the old "refresh snapshot, then build payload"
    /// pair so the content JSON is encoded once per cycle instead of twice.
    private func buildPayloadRefreshingSnapshot() async -> SyncPayload {
        let content = await buildPayloadContent()
        let contentData = try? sortedJSONEncoder.encode(content)
        let contentHash = contentData.map(Self.sha256Hex) ?? ""

        if !contentHash.isEmpty, contentHash != defaults.string(forKey: Keys.lastLocalHash) {
            defaults.set(contentHash, forKey: Keys.lastLocalHash)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastLocalUpdatedAt)
        }
        if defaults.double(forKey: Keys.lastLocalUpdatedAt) <= 0 {
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastLocalUpdatedAt)
        }

        let updatedAt = defaults.double(forKey: Keys.lastLocalUpdatedAt)
        return SyncPayload(
            schemaVersion: 7,
            updatedAt: max(0, updatedAt),
            contentHash: contentHash,
            settings: content.settings,
            filters: content.filters,
            userScripts: content.userScripts,
            whitelistDomains: content.whitelistDomains,
            filterDisabledDomains: content.filterDisabledDomains,
            noAutoplayEnabled: content.noAutoplayEnabled,
            noAutoplayAllowedSites: content.noAutoplayAllowedSites,
            zapperRules: content.zapperRules,
            zapperDisabledDomains: content.zapperDisabledDomains
        )
    }

    private func buildPayloadContent() async -> SyncPayload.Content {
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
            .map { FilterListLoader.canonicalFilterURLString($0.url.absoluteString) }
            .sorted()

        let selectedURLs = filterLists
            .filter { $0.isSelected }
            .map { FilterListLoader.canonicalFilterURLString($0.url.absoluteString) }
            .sorted()

        let customListURLs = filterLists
            .filter(\.isCustom)
            .filter { !deletedCustomURLSet().contains($0.url.absoluteString) }
            .map { $0.url.absoluteString }

        // Inline list contents are read from disk; fetch them off the main actor so
        // large lists don't block the UI while the payload is assembled.
        let inlineContents = await Self.readInlineUserListContents(for: customListURLs)

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
                    content: inlineContents[list.url.absoluteString]
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
        let currentLocalScripts = await userScriptManager.cloudSyncLocalUserScripts()
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
                    category: script.category.rawValue,
                    disabledHosts: disabledHosts
                )
            }
            .sorted { $0.url < $1.url }

        let deletedLocalNamesSet = deletedLocalUserScriptNameSet()
        let deletedLocalIdentitiesSet = deletedLocalUserScriptIdentitySet()
        let localScripts = currentLocalScripts
            .filter { script in
                guard script.isLocal else { return false }
                if let identity = CloudSyncLocalUserScriptReconciler.normalizedIdentity(script.localImportIdentity) {
                    return !deletedLocalIdentitiesSet.contains(identity)
                }
                return !deletedLocalNamesSet.contains(
                    CloudSyncLocalUserScriptReconciler.normalizedName(script.name)
                )
            }
            .map { script in
                let disabledHosts = Self.normalizedDisabledHosts(
                    userScriptDisabledHosts[script.id.uuidString] ?? [])
                return SyncPayload.LocalUserScript(
                    name: script.name,
                    content: script.content,
                    isEnabled: script.isEnabled,
                    description: script.description,
                    updatesAutomatically: script.updatesAutomatically,
                    category: script.category.rawValue,
                    localImportIdentity: script.localImportIdentity,
                    disabledHosts: disabledHosts
                )
            }
            .sorted { $0.name < $1.name }

        let deletedLocalNames = Array(deletedLocalNamesSet).sorted()
        let deletedLocalIdentities = Array(deletedLocalIdentitiesSet).sorted()
        let deletedRemoteURLs = Array(deletedRemoteUserScriptURLSet()).sorted()
        let userScripts = SyncPayload.UserScripts(
            remote: remoteScripts,
            local: localScripts,
            deletedLocalNames: deletedLocalNames.isEmpty ? nil : deletedLocalNames,
            deletedLocalIdentities: deletedLocalIdentities.isEmpty ? nil : deletedLocalIdentities,
            deletedRemoteURLs: deletedRemoteURLs.isEmpty ? nil : deletedRemoteURLs
        )

        let whitelistDomains = dataManager.getWhitelistedDomains().sorted()
        let filterDisabledDomains = dataManager.filterDisabledSites.sorted()
        let noAutoplayEnabled = dataManager.isNoAutoplayEnabled
        let noAutoplayAllowedSites = dataManager.noAutoplayAllowedSites.sorted()
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
            noAutoplayEnabled: noAutoplayEnabled,
            noAutoplayAllowedSites: noAutoplayAllowedSites,
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
        guard isCloudKitAvailable, let database else { throw CloudSyncError.cloudKitUnavailable }
        do {
            return try await database.record(for: recordID)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            return nil
        }
    }

    /// Low-level save with bounded retry for transient errors only (network, quota, etc.).
    /// `.serverRecordChanged` is intentionally re-thrown so the caller can reconcile the
    /// server record's definitions before retrying, rather than silently overwriting it.
    private func saveRecord(_ record: CKRecord, retryCount: Int = 0) async throws -> CKRecord {
        guard isCloudKitAvailable, let database else { throw CloudSyncError.cloudKitUnavailable }
        do {
            return try await database.save(record)
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
                currentPayload = await buildPayloadRefreshingSnapshot()
                var mutableRecord = serverRecord
                let payloadURL = try await applyPayloadFields(currentPayload, to: &mutableRecord)
                tempURLs.append(payloadURL)
                currentRecord = mutableRecord
            }
        }
    }

    private func applyPayloadFields(_ payload: SyncPayload, to record: inout CKRecord) async throws -> URL {
        let data = try sortedJSONEncoder.encode(payload)
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
        if !isCloudKitAvailable {
            lastErrorMessage = nil
            setStatus(.off)
            lastSyncLine = String(localized: "Not synced yet")
            return
        }

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
        setLastSyncedLocalUserScriptIdentities(localUserScriptIdentities(in: localPayload))
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
        refreshStatusFromDefaults()
        setStatus(.upToDate)
    }

    // MARK: - Helpers

    private func finishSyncCycle() {
        isSyncing = false

        if let syncTrigger = deferredInFlightSyncTrigger {
            deferredInFlightSyncTrigger = nil
            logger.info("Scheduling deferred sync (\(syncTrigger, privacy: .public))")
            Task { [weak self] in
                guard let self else { return }
                await self.syncNow(trigger: syncTrigger)
                // If the replayed sync was throttled away (or otherwise didn't run a full
                // cycle), it never reached its own finishSyncCycle, so drain any upload that
                // was deferred during the previous cycle here. No-op if already drained.
                if let deferred = self.uploadCoordinator.takeDeferredTrigger() {
                    self.scheduleUpload(trigger: deferred)
                }
            }
            return
        }

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
        static let deletedLocalUserScriptIdentities = "cloudSyncDeletedLocalUserScriptIdentities"
        static let lastSyncedLocalUserScriptNames = "cloudSyncLastSyncedLocalUserScriptNames"
        static let lastSyncedLocalUserScriptIdentities = "cloudSyncLastSyncedLocalUserScriptIdentities"
        static let deletedRemoteUserScriptURLs = "cloudSyncDeletedRemoteUserScriptURLs"
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func inlineUserListID(from urlString: String) -> UUID? {
        guard let url = URL(string: urlString) else { return nil }
        guard url.scheme?.lowercased() == "wblock" else { return nil }
        guard url.host?.lowercased() == "userlist" else { return nil }
        let idString = url.pathComponents.dropFirst().first
        guard let idString, let id = UUID(uuidString: idString) else { return nil }
        return id
    }

    /// Reads all inline user-list files in one off-actor pass so the main actor
    /// isn't blocked by synchronous disk I/O during payload assembly.
    private static func readInlineUserListContents(for urlStringList: [String]) async -> [String: String] {
        guard !urlStringList.isEmpty else { return [:] }
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) else {
            return [:]
        }
        // Resolve which files to read on the main actor (inlineUserListID is main-actor-isolated);
        // only the actual disk reads run off-actor.
        let fileURLs: [(String, URL)] = urlStringList.compactMap { urlString in
            guard let id = inlineUserListID(from: urlString) else { return nil }
            return (urlString, containerURL.appendingPathComponent("custom-\(id.uuidString).txt"))
        }
        guard !fileURLs.isEmpty else { return [:] }
        return await Task.detached(priority: .utility) { () -> [String: String] in
            var results: [String: String] = [:]
            for (urlString, fileURL) in fileURLs {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    results[urlString] = content
                }
            }
            return results
        }.value
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

    private static func parseDeletedTimestamp(_ value: Any?) -> TimeInterval? {
        if let t = value as? TimeInterval { return t }
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    private func loadDeletedMarkers(
        forKey key: String,
        normalize: (String) -> String = { $0 }
    ) -> [String: TimeInterval] {
        let raw = defaults.dictionary(forKey: key) ?? [:]
        var result: [String: TimeInterval] = [:]
        for (rawKey, value) in raw {
            let normalizedKey = normalize(rawKey)
            guard !normalizedKey.isEmpty, let t = Self.parseDeletedTimestamp(value) else { continue }
            result[normalizedKey] = t
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

    private func localUserScriptIdentities(in payload: SyncPayload) -> Set<String> {
        Set(
            payload.userScripts.local
                .compactMap { CloudSyncLocalUserScriptReconciler.normalizedIdentity($0.localImportIdentity) }
        )
    }

    private func lastSyncedLocalUserScriptNameSet() -> Set<String> {
        let raw = defaults.array(forKey: Keys.lastSyncedLocalUserScriptNames) as? [String] ?? []
        return Set(raw.map(CloudSyncLocalUserScriptReconciler.normalizedName).filter { !$0.isEmpty })
    }

    private func lastSyncedLocalUserScriptIdentitySet() -> Set<String> {
        let raw = defaults.array(forKey: Keys.lastSyncedLocalUserScriptIdentities) as? [String] ?? []
        return Set(raw.compactMap(CloudSyncLocalUserScriptReconciler.normalizedIdentity))
    }

    private func setLastSyncedLocalUserScriptNames(_ names: Set<String>) {
        let normalized = Set(
            names.map(CloudSyncLocalUserScriptReconciler.normalizedName).filter { !$0.isEmpty }
        )
        defaults.set(normalized.sorted(), forKey: Keys.lastSyncedLocalUserScriptNames)
    }

    private func setLastSyncedLocalUserScriptIdentities(_ identities: Set<String>) {
        let normalized = Set(identities.compactMap(CloudSyncLocalUserScriptReconciler.normalizedIdentity))
        defaults.set(normalized.sorted(), forKey: Keys.lastSyncedLocalUserScriptIdentities)
    }

    private func loadDeletedLocalUserScriptIdentityMarkers() -> [String: TimeInterval] {
        loadDeletedMarkers(
            forKey: Keys.deletedLocalUserScriptIdentities,
            normalize: { CloudSyncLocalUserScriptReconciler.normalizedIdentity($0) ?? "" }
        )
    }

    private func deletedLocalUserScriptNameSet() -> Set<String> {
        let markers = loadDeletedLocalUserScriptMarkers()
        return Set(markers.keys)
    }

    private func deletedLocalUserScriptIdentitySet() -> Set<String> {
        Set(loadDeletedLocalUserScriptIdentityMarkers().keys)
    }

    private func loadDeletedLocalUserScriptMarkers() -> [String: TimeInterval] {
        loadDeletedMarkers(forKey: Keys.deletedLocalUserScriptNames, normalize: CloudSyncLocalUserScriptReconciler.normalizedName)
    }

    private func mergeDeletedLocalUserScriptNames(_ names: Set<String>) {
        let normalized = Set(names.map(CloudSyncLocalUserScriptReconciler.normalizedName).filter { !$0.isEmpty })
        let markers = loadDeletedLocalUserScriptMarkers()
        mergeDeletedMarkers(normalized, markers: markers, saveKey: Keys.deletedLocalUserScriptNames)
    }

    private func mergeDeletedLocalUserScriptIdentities(_ identities: Set<String>) {
        let normalized = Set(identities.compactMap(CloudSyncLocalUserScriptReconciler.normalizedIdentity))
        guard !normalized.isEmpty else { return }
        let markers = loadDeletedLocalUserScriptIdentityMarkers()
        mergeDeletedMarkers(normalized, markers: markers, saveKey: Keys.deletedLocalUserScriptIdentities)
    }

    private func deletedRemoteUserScriptURLSet() -> Set<String> {
        let markers = loadDeletedRemoteUserScriptURLMarkers()
        return Set(markers.keys)
    }

    private func loadDeletedRemoteUserScriptURLMarkers() -> [String: TimeInterval] {
        loadDeletedMarkers(forKey: Keys.deletedRemoteUserScriptURLs, normalize: CloudSyncRemoteUserScriptReconciler.normalizedURL)
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

    struct RemoteUserScript: Codable, Sendable {
        let url: String
        let isEnabled: Bool
        let updatesAutomatically: Bool?
        /// Optional for compatibility with older CloudKit payloads.
        let category: String?
        let disabledHosts: [String]?

        var resolvedUpdatesAutomatically: Bool {
            updatesAutomatically ?? true
        }

        var resolvedCategory: FilterListCategory {
            FilterListCategory(rawValue: category ?? "") ?? .scripts
        }
    }

    struct LocalUserScript: Codable {
        let name: String
        let content: String
        let isEnabled: Bool
        /// Optional for compatibility with older CloudKit payloads.
        let description: String?
        let updatesAutomatically: Bool?
        /// Optional for compatibility with older CloudKit payloads.
        let category: String?
        /// Additive identity for local imports; absent in legacy payloads.
        let localImportIdentity: String?
        let disabledHosts: [String]?

        var resolvedUpdatesAutomatically: Bool {
            updatesAutomatically ?? true
        }

        var resolvedCategory: FilterListCategory {
            FilterListCategory(rawValue: category ?? "") ?? .scripts
        }
    }

    struct UserScripts: Codable {
        let remote: [RemoteUserScript]
        let local: [LocalUserScript]
        /// Optional additive identity tombstones; absent in legacy payloads.
        let deletedLocalNames: [String]?
        let deletedLocalIdentities: [String]?
        let deletedRemoteURLs: [String]?
    }

    struct Content: Codable {
        let settings: Settings
        let filters: Filters
        let userScripts: UserScripts
        let whitelistDomains: [String]
        let filterDisabledDomains: [String]?
        let noAutoplayEnabled: Bool?
        let noAutoplayAllowedSites: [String]?
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
    let noAutoplayEnabled: Bool?
    let noAutoplayAllowedSites: [String]?
    let zapperRules: [String: [String]]?
    let zapperDisabledDomains: [String]?
}

private extension SyncPayload.CustomFilterList {
    var resolvedCategory: FilterListCategory {
        FilterListCategory(rawValue: category ?? "") ?? .custom
    }
}
