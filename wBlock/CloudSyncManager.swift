import CloudKit
import Combine
import CryptoKit
import Foundation
import os.log
import wBlockCoreService

@MainActor
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var statusLine: String = "Sync: Off"
    @Published private(set) var lastSyncLine: String = "Last Sync: Never"
    @Published private(set) var lastErrorMessage: String?

    private weak var filterManager: AppFilterManager?

    private let logger = Logger(subsystem: "skula.wBlock", category: "CloudSync")
    private let dataManager = ProtobufDataManager.shared
    private let userScriptManager = UserScriptManager.shared

    private let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
    private let database = CKContainer.default().privateCloudDatabase
    private let recordID = CKRecord.ID(recordName: "wblock-sync-config")
    private let recordType = "wBlockSync"

    private var cancellables = Set<AnyCancellable>()
    private var pendingUploadTask: Task<Void, Never>?
    private var pendingSyncTask: Task<Void, Never>?
    private var isApplyingRemoteChanges: Bool = false

    private init() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        refreshStatusFromDefaults()
        observeLocalSaves()
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
        pendingSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.performTwoWaySync(trigger: trigger)
        }
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
            statusLine = "Sync: Downloading…"
            lastErrorMessage = nil
            defer { isSyncing = false }

            await applyRemotePayload(payload, trigger: trigger)
            logger.info("✅ Applied remote sync payload (\(trigger, privacy: .public))")
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            statusLine = "Sync: Error"
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

    private func handleLocalSave() {
        guard isEnabled else { return }
        guard !isApplyingRemoteChanges else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.dataManager.waitUntilLoaded()
            await self.userScriptManager.waitUntilReady()

            let localContent = self.buildPayloadContent()
            guard let localContentData = try? JSONEncoder.sorted.encode(localContent) else { return }
            let localHash = Self.sha256Hex(localContentData)

            if localHash != self.defaults.string(forKey: Keys.lastLocalHash) {
                self.defaults.set(localHash, forKey: Keys.lastLocalHash)
                self.defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastLocalUpdatedAt)
            }

            self.scheduleUpload(trigger: "LocalSave")
        }
    }

    private func scheduleUpload(trigger: String) {
        pendingUploadTask?.cancel()
        pendingUploadTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(2))
            await self.uploadLatestPayload(trigger: trigger)
        }
    }

    private func uploadLatestPayload(trigger: String) async {
        guard isEnabled else { return }
        await dataManager.waitUntilLoaded()
        await userScriptManager.waitUntilReady()

        do {
            isSyncing = true
            statusLine = "Sync: Uploading…"

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
                statusLine = "Sync: Up to date"
                isSyncing = false
                return
            }

            let payloadURL = try await applyPayloadFields(payload, to: &record)
            defer { try? FileManager.default.removeItem(at: payloadURL) }

            _ = try await saveRecord(record)

            defaults.set(payloadHash, forKey: Keys.lastUploadedHash)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastUploadedAt)
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
            lastErrorMessage = nil
            refreshStatusFromDefaults()

            logger.info("✅ Uploaded sync payload (\(trigger, privacy: .public))")
        } catch {
            lastErrorMessage = error.localizedDescription
            statusLine = "Sync: Error"
            logger.error("❌ Upload failed: \(error.localizedDescription, privacy: .public)")
        }

        isSyncing = false
    }

    // MARK: - Two-way sync

    private func performTwoWaySync(trigger: String) async {
        guard isEnabled else { return }
        await dataManager.waitUntilLoaded()
        await userScriptManager.waitUntilReady()

        if isSyncing { return }
        isSyncing = true
        statusLine = "Sync: Checking…"
        lastErrorMessage = nil

        do {
            let localPayload = buildPayload()
            let localUpdatedAt = localPayload.updatedAt

            guard let remoteRecord = try await fetchRecord() else {
                statusLine = "Sync: Uploading…"
                await uploadLatestPayload(trigger: "\(trigger)-NoRemote")
                isSyncing = false
                return
            }

            guard let remotePayload = try decodePayload(from: remoteRecord) else {
                statusLine = "Sync: Uploading…"
                await uploadLatestPayload(trigger: "\(trigger)-BadRemote")
                isSyncing = false
                return
            }

            if remotePayload.contentHash == localPayload.contentHash {
                defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastSyncAt)
                refreshStatusFromDefaults()
                statusLine = "Sync: Up to date"
                isSyncing = false
                return
            }

            if remotePayload.updatedAt > localUpdatedAt {
                statusLine = "Sync: Downloading…"
                await applyRemotePayload(remotePayload, trigger: trigger)
            } else {
                statusLine = "Sync: Uploading…"
                await uploadLatestPayload(trigger: "\(trigger)-LocalNewer")
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            statusLine = "Sync: Error"
            logger.error("❌ Sync failed: \(error.localizedDescription, privacy: .public)")
        }

        isSyncing = false
    }

    private func applyRemotePayload(_ payload: SyncPayload, trigger: String) async {
        logger.info("⬇️ Applying remote payload (\(trigger, privacy: .public))")
        isApplyingRemoteChanges = true
        defer { isApplyingRemoteChanges = false }

        // Settings
        await dataManager.setSelectedBlockingLevel(payload.settings.selectedBlockingLevel)
        await dataManager.setIsBadgeCounterEnabled(payload.settings.isBadgeCounterEnabled)
        await dataManager.setAutoUpdateEnabled(payload.settings.autoUpdateEnabled)
        await dataManager.setAutoUpdateIntervalHours(payload.settings.autoUpdateIntervalHours)
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
            await filterManager.applyChanges()
        }
    }

    private func applyRemoteFilters(_ filters: SyncPayload.Filters) async {
        let desiredSelected = Set(filters.selectedURLs)
        let knownURLs = Set(filters.knownURLs ?? filters.selectedURLs)

        if let filterManager {
            var changed = false

            // Update selection for all non-custom filters by URL
            for index in filterManager.filterLists.indices {
                guard !filterManager.filterLists[index].isCustom else { continue }
                let urlString = filterManager.filterLists[index].url.absoluteString
                guard knownURLs.contains(urlString) else { continue }
                let shouldSelect = desiredSelected.contains(urlString)
                if filterManager.filterLists[index].isSelected != shouldSelect {
                    filterManager.filterLists[index].isSelected = shouldSelect
                    changed = true
                }
            }

            // Upsert custom lists from remote
            for remoteCustom in filters.customLists {
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
                        filterManager.customFilterLists.removeAll { $0.id == existing.id }
                        changed = true
                        shouldTreatAsMissing = true
                    }

                    if !shouldTreatAsMissing {
                        if filterManager.filterLists[existingIndex].name != remoteCustom.name {
                            filterManager.filterLists[existingIndex].name = remoteCustom.name
                            changed = true
                        }
                        if let desc = remoteCustom.description,
                           filterManager.filterLists[existingIndex].description != desc
                        {
                            filterManager.filterLists[existingIndex].description = desc
                            changed = true
                        }
                        if filterManager.filterLists[existingIndex].isSelected != remoteCustom.isSelected {
                            filterManager.filterLists[existingIndex].isSelected = remoteCustom.isSelected
                            changed = true
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
                        filterManager.customFilterLists.append(newFilter)
                        filterManager.filterLists.append(newFilter)
                        changed = true
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
                    filterManager.customFilterLists.append(newFilter)
                    filterManager.filterLists.append(newFilter)
                    changed = true
                }
            }

            if changed {
                filterManager.hasUnappliedChanges = true
                await filterManager.saveFilterLists()
            }
            return
        }

        // Fallback: update persisted lists without touching the in-memory manager.
        var storedLists = dataManager.getFilterLists()

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

        for remoteCustom in filters.customLists {
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
        // Remote scripts (URL-based)
        // Ensure each desired remote script exists and has the correct enabled state.
        for remote in scripts.remote {
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
        // Import or replace local scripts from the remote payload. Do not remove local-only scripts.
        for local in scripts.local {
            if let existing = userScriptManager.userScripts.first(where: { $0.isLocal && $0.name == local.name }) {
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

            if let imported = userScriptManager.userScripts.first(where: { $0.isLocal && $0.name == local.name }) {
                await userScriptManager.setUserScript(imported, isEnabled: local.isEnabled)
            }
        }
    }

    private func reconcileMissingDefinitionsIfNeeded(from remotePayload: SyncPayload) async {
        // Import missing custom filter lists and userscripts before uploading so we don't
        // accidentally drop them from the single shared CloudKit payload.

        let localCustomURLs: Set<String> = Set(dataManager.getCustomFilterLists().map { $0.url.absoluteString })
        let remoteCustoms = remotePayload.filters.customLists
        let missingCustoms = remoteCustoms.filter { !localCustomURLs.contains($0.url) }

        let localRemoteScriptURLs: Set<String> = Set(
            userScriptManager.userScripts.compactMap { script in
                guard !script.isLocal, let url = script.url else { return nil }
                return url.absoluteString
            }
        )
        let remoteRemoteScripts = remotePayload.userScripts.remote
        let missingRemoteScripts = remoteRemoteScripts.filter { !localRemoteScriptURLs.contains($0.url) }

        let localLocalNames = Set(userScriptManager.userScripts.filter(\.isLocal).map(\.name))
        let remoteLocalScripts = remotePayload.userScripts.local
        let missingLocalScripts = remoteLocalScripts.filter { !localLocalNames.contains($0.name) }

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
                    filterManager.customFilterLists.append(newFilter)
                    filterManager.filterLists.append(newFilter)
                    changed = true
                }
                if changed {
                    filterManager.hasUnappliedChanges = true
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
            if let imported = userScriptManager.userScripts.first(where: { $0.isLocal && $0.name == local.name }) {
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
            schemaVersion: 3,
            updatedAt: max(0, updatedAt),
            contentHash: contentHash,
            settings: content.settings,
            filters: content.filters,
            userScripts: content.userScripts,
            whitelistDomains: content.whitelistDomains
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

        let filterLists = dataManager.getFilterLists()
        let knownURLs = filterLists
            .filter { !$0.isCustom }
            .map { $0.url.absoluteString }
            .sorted()

        let selectedURLs = filterLists
            .filter { $0.isSelected }
            .map { $0.url.absoluteString }
            .sorted()

        let customLists = dataManager.getCustomFilterLists()
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

        let filters = SyncPayload.Filters(
            knownURLs: knownURLs,
            selectedURLs: selectedURLs,
            customLists: customLists
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

        let userScripts = SyncPayload.UserScripts(remote: remoteScripts, local: localScripts)

        let whitelistDomains = dataManager.getWhitelistedDomains().sorted()

        return SyncPayload.Content(
            settings: settings,
            filters: filters,
            userScripts: userScripts,
            whitelistDomains: whitelistDomains
        )
    }

    // MARK: - CloudKit I/O

    private func fetchRecord() async throws -> CKRecord? {
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

    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: saved ?? record)
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
            statusLine = "Sync: Off"
            lastSyncLine = "Last Sync: Never"
            return
        }

        statusLine = isSyncing ? "Sync: Working…" : "Sync: On"

        let lastSyncAt = defaults.double(forKey: Keys.lastSyncAt)
        if lastSyncAt > 0 {
            lastSyncLine = "Last Sync: \(Self.relativeDateString(from: Date(timeIntervalSince1970: lastSyncAt)))"
        } else {
            lastSyncLine = "Last Sync: Never"
        }
    }

    // MARK: - Helpers

    private enum Keys {
        static let enabled = "cloudSyncEnabled"
        static let lastLocalHash = "cloudSyncLastLocalHash"
        static let lastLocalUpdatedAt = "cloudSyncLastLocalUpdatedAt"
        static let lastUploadedHash = "cloudSyncLastUploadedHash"
        static let lastUploadedAt = "cloudSyncLastUploadedAt"
        static let lastDownloadedHash = "cloudSyncLastDownloadedHash"
        static let lastDownloadedAt = "cloudSyncLastDownloadedAt"
        static let lastSyncAt = "cloudSyncLastSyncAt"
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

    private static func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
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
    }

    struct Content: Codable {
        let settings: Settings
        let filters: Filters
        let userScripts: UserScripts
        let whitelistDomains: [String]
    }

    let schemaVersion: Int
    let updatedAt: TimeInterval
    let contentHash: String
    let settings: Settings
    let filters: Filters
    let userScripts: UserScripts
    let whitelistDomains: [String]
}
