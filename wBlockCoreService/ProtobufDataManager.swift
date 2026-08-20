//
//  ProtobufDataManager.swift
//  wBlockCoreService
//
//  Created by Alexander Skula on 8/13/25.
//

import Foundation
internal import SwiftProtobuf
import Combine
import os.log

private func mergeField<T: Equatable>(_ local: inout T, baseline: T, persisted: T) {
    if local == baseline { local = persisted }
}

private func mergeMap<Key: Hashable, Value: Equatable>(
    _ local: inout [Key: Value],
    baseline: [Key: Value],
    persisted: [Key: Value]
) {
    let keys = Set(baseline.keys).union(local.keys).union(persisted.keys)
    for key in keys where local[key] == baseline[key] {
        local[key] = persisted[key]
    }
}

private func mergeStringSet(
    _ local: inout [String],
    baseline: [String],
    persisted: [String]
) {
    let baselineSet = Set(baseline)
    let localSet = Set(local)
    var merged = Set(persisted)
    merged.subtract(baselineSet.subtracting(localSet))
    merged.formUnion(localSet.subtracting(baselineSet))
    local = merged.sorted()
}

private func mergeSettings(
    _ local: inout Wblock_Data_AppSettings,
    baseline: Wblock_Data_AppSettings,
    persisted: Wblock_Data_AppSettings
) {
    mergeField(&local.hasCompletedOnboarding_p, baseline: baseline.hasCompletedOnboarding_p, persisted: persisted.hasCompletedOnboarding_p)
    mergeField(&local.selectedBlockingLevel, baseline: baseline.selectedBlockingLevel, persisted: persisted.selectedBlockingLevel)
    mergeField(&local.lastUpdateCheck, baseline: baseline.lastUpdateCheck, persisted: persisted.lastUpdateCheck)
    mergeField(&local.showAdvancedFeatures, baseline: baseline.showAdvancedFeatures, persisted: persisted.showAdvancedFeatures)
    mergeField(&local.appVersion, baseline: baseline.appVersion, persisted: persisted.appVersion)
    mergeField(&local.lastTerminologySanitizationVersion, baseline: baseline.lastTerminologySanitizationVersion, persisted: persisted.lastTerminologySanitizationVersion)
    mergeField(&local.hasEnabledContentBlockers_p, baseline: baseline.hasEnabledContentBlockers_p, persisted: persisted.hasEnabledContentBlockers_p)
    mergeField(&local.hasEnabledPlatformExtension_p, baseline: baseline.hasEnabledPlatformExtension_p, persisted: persisted.hasEnabledPlatformExtension_p)
    mergeField(&local.hasSetAllWebsitesPermission_p, baseline: baseline.hasSetAllWebsitesPermission_p, persisted: persisted.hasSetAllWebsitesPermission_p)
    mergeField(&local.userscriptShowEnabledOnly, baseline: baseline.userscriptShowEnabledOnly, persisted: persisted.userscriptShowEnabledOnly)
    mergeStringSet(
        &local.excludedDefaultUserscriptUrls,
        baseline: baseline.excludedDefaultUserscriptUrls,
        persisted: persisted.excludedDefaultUserscriptUrls
    )
    mergeField(&local.isForeignFiltersExpanded, baseline: baseline.isForeignFiltersExpanded, persisted: persisted.isForeignFiltersExpanded)
    mergeField(&local.isBadgeCounterEnabled, baseline: baseline.isBadgeCounterEnabled, persisted: persisted.isBadgeCounterEnabled)
    mergeField(&local.unknownFields, baseline: baseline.unknownFields, persisted: persisted.unknownFields)
}

// Key paths retained in this merge contract: \.filterLists, \.userScripts, \.userScriptDisabledHosts.
private func mergeFilterLists(
    _ local: inout [Wblock_Data_FilterListData],
    baseline: [Wblock_Data_FilterListData],
    persisted: [Wblock_Data_FilterListData],
    deletedIDs: Set<String>
) {
    let baselineByID = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    let persistedByID = Dictionary(persisted.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    var ids = persisted.map(\.id)
    ids.append(contentsOf: local.map(\.id).filter { !ids.contains($0) })
    local = ids.compactMap { id in
        if deletedIDs.contains(id) { return nil }
        guard let mine = localByID[id] else { return persistedByID[id] }
        guard let theirs = persistedByID[id], let base = baselineByID[id] else { return mine }
        var merged = mine
        mergeField(&merged.name, baseline: base.name, persisted: theirs.name)
        mergeField(&merged.url, baseline: base.url, persisted: theirs.url)
        mergeField(&merged.category, baseline: base.category, persisted: theirs.category)
        mergeField(&merged.isSelected, baseline: base.isSelected, persisted: theirs.isSelected)
        mergeField(&merged.description_p, baseline: base.description_p, persisted: theirs.description_p)
        mergeField(&merged.version, baseline: base.version, persisted: theirs.version)
        if merged.hasSourceRuleCount == base.hasSourceRuleCount
            && (!merged.hasSourceRuleCount || merged.sourceRuleCount == base.sourceRuleCount)
        {
            if theirs.hasSourceRuleCount { merged.sourceRuleCount = theirs.sourceRuleCount }
            else { merged.clearSourceRuleCount() }
        }
        mergeField(&merged.lastUpdated, baseline: base.lastUpdated, persisted: theirs.lastUpdated)
        mergeField(&merged.isCustom, baseline: base.isCustom, persisted: theirs.isCustom)
        mergeField(&merged.localFilePath, baseline: base.localFilePath, persisted: theirs.localFilePath)
        mergeField(&merged.unknownFields, baseline: base.unknownFields, persisted: theirs.unknownFields)
        return merged
    }
}

private func mergePersistedChanges(
    in snapshot: inout Wblock_Data_AppData,
    comparedTo previous: Wblock_Data_AppData,
    from persisted: Wblock_Data_AppData,
    explicitlyDeletedFilterIDs: Set<String> = []
) {
    var settings = snapshot.settings
    mergeSettings(&settings, baseline: previous.settings, persisted: persisted.settings)
    snapshot.settings = settings
    mergeFilterLists(&snapshot.filterLists, baseline: previous.filterLists, persisted: persisted.filterLists, deletedIDs: explicitlyDeletedFilterIDs)

    var explicitEnabledStates: [String: Bool] = [:]
    let previousScriptsByID = Dictionary(uniqueKeysWithValues: previous.userScripts.map { ($0.id, $0) })
    for script in snapshot.userScripts where previousScriptsByID[script.id]?.isEnabled != script.isEnabled {
        explicitEnabledStates[script.id] = script.isEnabled
    }
    snapshot.userScripts = UserScriptPersistence.merge(persisted: persisted.userScripts, incoming: snapshot.userScripts, explicitEnabledStates: explicitEnabledStates)

    var whitelist = snapshot.whitelist
    mergeStringSet(
        &whitelist.disabledSites,
        baseline: previous.whitelist.disabledSites,
        persisted: persisted.whitelist.disabledSites
    )
    mergeStringSet(
        &whitelist.filterDisabledSites,
        baseline: previous.whitelist.filterDisabledSites,
        persisted: persisted.whitelist.filterDisabledSites
    )
    mergeField(
        &whitelist.noAutoplayEnabled,
        baseline: previous.whitelist.noAutoplayEnabled,
        persisted: persisted.whitelist.noAutoplayEnabled
    )
    mergeStringSet(
        &whitelist.noAutoplayAllowedSites,
        baseline: previous.whitelist.noAutoplayAllowedSites,
        persisted: persisted.whitelist.noAutoplayAllowedSites
    )
    whitelist.lastUpdated = max(whitelist.lastUpdated, persisted.whitelist.lastUpdated)
    mergeField(
        &whitelist.unknownFields,
        baseline: previous.whitelist.unknownFields,
        persisted: persisted.whitelist.unknownFields
    )
    snapshot.whitelist = whitelist

    var counts = snapshot.ruleCounts
    mergeField(&counts.lastRuleCount, baseline: previous.ruleCounts.lastRuleCount, persisted: persisted.ruleCounts.lastRuleCount)
    mergeMap(
        &counts.ruleCountsByCategory,
        baseline: previous.ruleCounts.ruleCountsByCategory,
        persisted: persisted.ruleCounts.ruleCountsByCategory
    )
    mergeField(&counts.categoriesApproachingLimit, baseline: previous.ruleCounts.categoriesApproachingLimit, persisted: persisted.ruleCounts.categoriesApproachingLimit)
    mergeField(&counts.lastUpdated, baseline: previous.ruleCounts.lastUpdated, persisted: persisted.ruleCounts.lastUpdated)
    mergeField(&counts.unknownFields, baseline: previous.ruleCounts.unknownFields, persisted: persisted.ruleCounts.unknownFields)
    snapshot.ruleCounts = counts

    var performance = snapshot.performance
    mergeField(&performance.lastConversionTime, baseline: previous.performance.lastConversionTime, persisted: persisted.performance.lastConversionTime)
    mergeField(&performance.lastReloadTime, baseline: previous.performance.lastReloadTime, persisted: persisted.performance.lastReloadTime)
    mergeField(&performance.lastFastUpdateTime, baseline: previous.performance.lastFastUpdateTime, persisted: persisted.performance.lastFastUpdateTime)
    mergeField(&performance.fastUpdateCount, baseline: previous.performance.fastUpdateCount, persisted: persisted.performance.fastUpdateCount)
    mergeField(&performance.sourceRulesCount, baseline: previous.performance.sourceRulesCount, persisted: persisted.performance.sourceRulesCount)
    mergeField(&performance.conversionStageDescription, baseline: previous.performance.conversionStageDescription, persisted: persisted.performance.conversionStageDescription)
    mergeField(&performance.currentFilterName, baseline: previous.performance.currentFilterName, persisted: persisted.performance.currentFilterName)
    mergeField(&performance.processedFiltersCount, baseline: previous.performance.processedFiltersCount, persisted: persisted.performance.processedFiltersCount)
    mergeField(&performance.totalFiltersCount, baseline: previous.performance.totalFiltersCount, persisted: persisted.performance.totalFiltersCount)
    mergeField(&performance.currentPlatform, baseline: previous.performance.currentPlatform, persisted: persisted.performance.currentPlatform)
    mergeField(&performance.unknownFields, baseline: previous.performance.unknownFields, persisted: persisted.performance.unknownFields)
    snapshot.performance = performance

    var extensionData = snapshot.extensionData
    mergeMap(
        &extensionData.tabBlockedRequests,
        baseline: previous.extensionData.tabBlockedRequests,
        persisted: persisted.extensionData.tabBlockedRequests
    )
    mergeField(&extensionData.zapperRules, baseline: previous.extensionData.zapperRules, persisted: persisted.extensionData.zapperRules)
    mergeMap(
        &extensionData.zapperRulesByHost,
        baseline: previous.extensionData.zapperRulesByHost,
        persisted: persisted.extensionData.zapperRulesByHost
    )
    extensionData.lastUpdated = max(extensionData.lastUpdated, persisted.extensionData.lastUpdated)
    mergeField(&extensionData.unknownFields, baseline: previous.extensionData.unknownFields, persisted: persisted.extensionData.unknownFields)
    snapshot.extensionData = extensionData

    var exceptions = snapshot.userScriptDisabledHosts
    mergeMap(
        &exceptions,
        baseline: previous.userScriptDisabledHosts,
        persisted: persisted.userScriptDisabledHosts
    )
    snapshot.userScriptDisabledHosts = exceptions

    var autoUpdate = snapshot.autoUpdate
    let base = previous.autoUpdate, theirs = persisted.autoUpdate
    mergeField(&autoUpdate.enabled, baseline: base.enabled, persisted: theirs.enabled)
    mergeField(&autoUpdate.intervalHours, baseline: base.intervalHours, persisted: theirs.intervalHours)
    mergeField(&autoUpdate.lastCheckTime, baseline: base.lastCheckTime, persisted: theirs.lastCheckTime)
    mergeField(&autoUpdate.lastSuccessfulTime, baseline: base.lastSuccessfulTime, persisted: theirs.lastSuccessfulTime)
    mergeField(&autoUpdate.nextEligibleTime, baseline: base.nextEligibleTime, persisted: theirs.nextEligibleTime)
    mergeField(&autoUpdate.forceNext, baseline: base.forceNext, persisted: theirs.forceNext)
    mergeField(&autoUpdate.isRunning, baseline: base.isRunning, persisted: theirs.isRunning)
    mergeField(&autoUpdate.runningSinceTimestamp, baseline: base.runningSinceTimestamp, persisted: theirs.runningSinceTimestamp)
    mergeMap(&autoUpdate.filterEtags, baseline: base.filterEtags, persisted: theirs.filterEtags)
    mergeMap(&autoUpdate.filterLastModified, baseline: base.filterLastModified, persisted: theirs.filterLastModified)
    mergeField(&autoUpdate.bgAppRefresh, baseline: base.bgAppRefresh, persisted: theirs.bgAppRefresh)
    mergeField(&autoUpdate.bgProcessing, baseline: base.bgProcessing, persisted: theirs.bgProcessing)
    mergeField(&autoUpdate.silentPush, baseline: base.silentPush, persisted: theirs.silentPush)
    mergeField(&autoUpdate.lastForegroundCatchUpTime, baseline: base.lastForegroundCatchUpTime, persisted: theirs.lastForegroundCatchUpTime)
    mergeField(&autoUpdate.lastForegroundCatchUpReason, baseline: base.lastForegroundCatchUpReason, persisted: theirs.lastForegroundCatchUpReason)
    mergeField(&autoUpdate.backgroundAgentDisabled, baseline: base.backgroundAgentDisabled, persisted: theirs.backgroundAgentDisabled)
    mergeField(&autoUpdate.unknownFields, baseline: base.unknownFields, persisted: theirs.unknownFields)
    snapshot.autoUpdate = autoUpdate
    mergeField(&snapshot.unknownFields, baseline: previous.unknownFields, persisted: persisted.unknownFields)
}

// MARK: - Disk I/O (off MainActor)

/// Performs protobuf file reads/writes off the MainActor to avoid UI stalls.
/// An actor is used so reads/writes are serialized.
private actor ProtobufDiskStore {
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.skula.wBlock", category: "ProtobufDiskStore")

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func modificationDate(for url: URL) -> Date? {
        guard fileExists(at: url) else { return nil }
        return (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    func readAppData(from url: URL) throws -> (appData: Wblock_Data_AppData, rawData: Data, modificationDate: Date?) {
        let rawData = try Data(contentsOf: url)
        let appData = try Wblock_Data_AppData(serializedBytes: rawData)
        return (appData: appData, rawData: rawData, modificationDate: modificationDate(for: url))
    }

    func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func dataVersion(for url: URL) -> Int64 {
        guard fileExists(at: url),
              let rawVersion = try? Data(contentsOf: url),
              let stringVersion = String(data: rawVersion, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let version = Int64(stringVersion) else {
            return 0
        }
        return max(version, 0)
    }

    private func writeDataVersion(_ version: Int64, to url: URL) throws {
        let rawVersion = Data(String(max(version, 0)).utf8)
        try writeData(rawVersion, to: url)
    }

    private func withExclusiveFileLock<T>(for dataURL: URL, _ operation: () throws -> T) throws -> T {
        try withCoordinatedWriteAccess(for: dataURL, operation)
    }

    private func withCoordinatedWriteAccess<T>(for dataURL: URL, _ operation: () throws -> T) throws -> T {
        let directoryURL = dataURL.deletingLastPathComponent()
        if !fileExists(at: directoryURL) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        // Coordinate the file rather than the whole shared directory once it exists.
        // The directory is only needed for first-write creation; narrower coordination
        // reduces the suspension window for unrelated app-group files.
        let coordinationURL = fileExists(at: dataURL) ? dataURL : directoryURL
        let startedAt = Date()
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationResult: Result<T, Error>?

        coordinator.coordinate(writingItemAt: coordinationURL, options: [], error: &coordinationError) { _ in
            operationResult = Result { try operation() }
        }

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        if durationMs >= 100 {
            logger.warning(
                "File coordination held for \(durationMs) ms: \(dataURL.lastPathComponent)"
            )
        }

        if let operationResult {
            return try operationResult.get()
        }

        if let coordinationError {
            throw coordinationError
        }

        throw NSError(
            domain: "ProtobufDiskStore",
            code: CocoaError.fileWriteUnknown.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "File coordination failed before protobuf write"]
        )
    }

    private func readCurrentAppData(from dataURL: URL) throws -> (rawData: Data?, appData: Wblock_Data_AppData) {
        guard fileExists(at: dataURL) else {
            return (rawData: nil, appData: Wblock_Data_AppData())
        }

        let rawData = try Data(contentsOf: dataURL)
        return (rawData: rawData, appData: try Wblock_Data_AppData(serializedBytes: rawData))
    }


    private func mutateAppDataOnce<Result: Sendable>(
        at dataURL: URL,
        versionURL: URL,
        mutate: @Sendable (inout Wblock_Data_AppData) -> Result
    ) throws -> (
        appData: Wblock_Data_AppData,
        rawData: Data,
        modificationDate: Date?,
        version: Int64,
        didWrite: Bool,
        result: Result
    ) {
        let current = try readCurrentAppData(from: dataURL)
        var workingData = current.appData

        let mutationResult = mutate(&workingData)
        let updatedRawData = try workingData.serializedData()
        let currentVersion = dataVersion(for: versionURL)

        if current.rawData == updatedRawData {
            return (
                appData: workingData,
                rawData: updatedRawData,
                modificationDate: modificationDate(for: dataURL),
                version: currentVersion,
                didWrite: false,
                result: mutationResult
            )
        }

        try writeData(updatedRawData, to: dataURL)
        let nextVersion = currentVersion + 1
        try writeDataVersion(nextVersion, to: versionURL)

        return (
            appData: workingData,
            rawData: updatedRawData,
            modificationDate: modificationDate(for: dataURL),
            version: nextVersion,
            didWrite: true,
            result: mutationResult
        )
    }


    private func writeAppDataIfChangedOnce(
        appData: Wblock_Data_AppData,
        previousData: Data?,
        explicitlyDeletedFilterIDs: Set<String> = [],
        to dataURL: URL,
        versionURL: URL
    ) throws -> (appData: Wblock_Data_AppData, rawData: Data, modificationDate: Date?, version: Int64, didWrite: Bool)? {
        let current = try readCurrentAppData(from: dataURL)
        var mergedSnapshot = appData

        if let persistedRawData = current.rawData,
           let previousData,
           previousData != persistedRawData {
            let previousSnapshot = try Wblock_Data_AppData(serializedBytes: previousData)
            mergePersistedChanges(
                in: &mergedSnapshot,
                comparedTo: previousSnapshot,
                from: current.appData,
                explicitlyDeletedFilterIDs: explicitlyDeletedFilterIDs
            )
        }

        let rawData = try mergedSnapshot.serializedData()
        if current.rawData == rawData {
            return (
                appData: mergedSnapshot,
                rawData: rawData,
                modificationDate: modificationDate(for: dataURL),
                version: dataVersion(for: versionURL),
                didWrite: false
            )
        }

        try writeData(rawData, to: dataURL)

        let nextVersion = dataVersion(for: versionURL) + 1
        try writeDataVersion(nextVersion, to: versionURL)

        return (appData: mergedSnapshot, rawData: rawData, modificationDate: modificationDate(for: dataURL), version: nextVersion, didWrite: true)
    }


    func mutateAppDataAtomically<Result: Sendable>(
        at dataURL: URL,
        versionURL: URL,
        mutate: @Sendable (inout Wblock_Data_AppData) -> Result
    ) throws -> (
        appData: Wblock_Data_AppData,
        rawData: Data,
        modificationDate: Date?,
        version: Int64,
        didWrite: Bool,
        result: Result
    ) {
        return try withExclusiveFileLock(for: dataURL) {
            try mutateAppDataOnce(at: dataURL, versionURL: versionURL, mutate: mutate)
        }
    }

    func writeAppDataIfChanged(
        appData: Wblock_Data_AppData,
        previousData: Data?,
        explicitlyDeletedFilterIDs: Set<String> = [],
        to dataURL: URL,
        versionURL: URL
    ) throws -> (appData: Wblock_Data_AppData, rawData: Data, modificationDate: Date?, version: Int64, didWrite: Bool)? {
        return try withExclusiveFileLock(for: dataURL) {
            try writeAppDataIfChangedOnce(
                appData: appData,
                previousData: previousData,
                explicitlyDeletedFilterIDs: explicitlyDeletedFilterIDs,
                to: dataURL,
                versionURL: versionURL
            )
        }
    }

    func removeItemIfExists(at url: URL) throws {
        guard fileExists(at: url) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Deletes all protobuf artifacts while holding the same coordination used by writes.
    /// Reset is therefore one serialized storage transaction, not three independent deletes.
    func resetFiles(dataURL: URL, backupURL: URL, versionURL: URL) throws {
        try withExclusiveFileLock(for: dataURL) {
            for url in [dataURL, backupURL, versionURL] where fileExists(at: url) {
                try fileManager.removeItem(at: url)
            }
        }
    }
}

/// Centralized data manager using Protocol Buffers for efficient, type-safe data storage
/// Replaces UserDefaults and SwiftData
public enum AutoUpdateDiagnosticTaskKind: Sendable {
    case appRefresh
    case processing
}

public enum AutoUpdateDiagnosticResult: String, Sendable {
    case registered = "registered"
    case failed = "failed"
    case submitted = "submitted"
    case infoPlistMissing = "info_plist_missing"
    case tooManyPending = "too_many_pending"
    case unavailable = "unavailable"
    case schedulerError = "scheduler_error"
    case submitFailed = "submit_failed"
    case completed = "completed"
    case timedOut = "timed_out"
    case deferred = "deferred"
    case overdue = "overdue"
    case dueSoon = "due_soon"
    case recorded = "recorded"
}

public struct BackgroundTaskDiagnosticsSnapshot: Sendable {
    public let lastScheduleAttemptTime: Int64
    public let lastScheduleResult: String
    public let lastScheduleError: String
    public let lastStartTime: Int64
    public let lastCompletionTime: Int64
    public let lastCompletionResult: String
    public let lastExpirationTime: Int64
}

public struct AutoUpdateDiagnosticsSnapshot: Sendable {
    public let bgAppRefresh: BackgroundTaskDiagnosticsSnapshot
    public let bgProcessing: BackgroundTaskDiagnosticsSnapshot
    public let lastForegroundCatchUpTime: Int64
    public let lastForegroundCatchUpReason: String
}

@MainActor
public class ProtobufDataManager: ObservableObject {
    /// Publishes after a successful on-disk save of the protobuf file.
    /// Useful for cross-process features (e.g. sync) that should react only when data is persisted.
    public var didSaveData: AnyPublisher<Void, Never> {
        didSaveDataSubject.eraseToAnyPublisher()
    }

    public var lastRuleCount: Int {
        Int(appData.ruleCounts.lastRuleCount)
    }

    public var ruleCountsByCategory: [String: Int32] {
        appData.ruleCounts.ruleCountsByCategory
    }

    public var categoriesApproachingLimit: [String] {
        appData.ruleCounts.categoriesApproachingLimit
    }

    public var disabledSites: [String] {
        appData.whitelist.disabledSites
    }

    public var filterDisabledSites: [String] {
        appData.whitelist.filterDisabledSites
    }


    public var whitelistLastUpdated: Int64 {
        appData.whitelist.lastUpdated
    }
    public var selectedBlockingLevel: String {
        appData.settings.selectedBlockingLevel
    }

    @MainActor
    @discardableResult
    public func setHasCompletedOnboarding(_ value: Bool) async -> Bool {
        guard await saveDataImmediately() else { return false }
        return await updateDataImmediately { $0.settings.hasCompletedOnboarding_p = value }
    }

    @MainActor
    public func setSelectedBlockingLevel(_ value: String) async {
        await updateData { $0.settings.selectedBlockingLevel = value }
    }
    public var hasCompletedOnboarding: Bool {
        appData.settings.hasCompletedOnboarding_p
    }

    // MARK: - Critical Setup State

    /// Indicates if all content blocker extensions have been enabled
    public var hasEnabledContentBlockers: Bool {
        appData.settings.hasEnabledContentBlockers_p
    }

    /// Indicates if wBlock Scripts has been enabled
    public var hasEnabledPlatformExtension: Bool {
        appData.settings.hasEnabledPlatformExtension_p
    }

    /// Indicates if all extensions have been set to "Allow on All Websites"
    public var hasSetAllWebsitesPermission: Bool {
        appData.settings.hasSetAllWebsitesPermission_p
    }

    /// Indicates if the critical setup checklist has been completed
    public var hasCompletedCriticalSetup: Bool {
        hasEnabledContentBlockers && hasEnabledPlatformExtension && hasSetAllWebsitesPermission
    }

    @MainActor
    public func setHasEnabledContentBlockers(_ value: Bool) async {
        await updateData { $0.settings.hasEnabledContentBlockers_p = value }
    }

    @MainActor
    public func setHasEnabledPlatformExtension(_ value: Bool) async {
        await updateData { $0.settings.hasEnabledPlatformExtension_p = value }
    }

    @MainActor
    public func setHasSetAllWebsitesPermission(_ value: Bool) async {
        await updateData { $0.settings.hasSetAllWebsitesPermission_p = value }
    }

    // MARK: - Filter UI State

    /// Indicates if the foreign filters section is expanded
    public var isForeignFiltersExpanded: Bool {
        appData.settings.isForeignFiltersExpanded
    }

    @MainActor
    public func setIsForeignFiltersExpanded(_ value: Bool) async {
        await updateData { $0.settings.isForeignFiltersExpanded = value }
    }

    // MARK: - Badge Counter Setting

    /// Indicates if badge counter is enabled
    public var isBadgeCounterEnabled: Bool {
        appData.settings.isBadgeCounterEnabled
    }

    @MainActor
    public func setIsBadgeCounterEnabled(_ value: Bool) async {
        await updateData { $0.settings.isBadgeCounterEnabled = value }
    }

    // MARK: - Auto-Update Settings

    /// Indicates if auto-update is enabled
    public var autoUpdateEnabled: Bool {
        appData.autoUpdate.enabled
    }

    @MainActor
    public func setAutoUpdateEnabled(_ value: Bool) async {
        await updateData { $0.autoUpdate.enabled = value }
    }

    /// Auto-update interval in hours
    public var autoUpdateIntervalHours: Double {
        appData.autoUpdate.intervalHours
    }

    @MainActor
    public func setAutoUpdateIntervalHours(_ value: Double) async {
        await updateData { $0.autoUpdate.intervalHours = value }
    }

    /// User preference to opt out of the persistent macOS background agent
    /// (login item) while keeping auto-updates enabled. Stored inverted so the
    /// proto3 default (false) preserves the historical behavior of running the
    /// agent whenever auto-update is enabled.
    public var backgroundAgentDisabled: Bool {
        appData.autoUpdate.backgroundAgentDisabled
    }

    @MainActor
    public func setBackgroundAgentDisabled(_ value: Bool) async {
        await updateData { $0.autoUpdate.backgroundAgentDisabled = value }
    }

    /// Last auto-update check time (Unix timestamp)
    public var autoUpdateLastCheckTime: Int64 {
        appData.autoUpdate.lastCheckTime
    }

    @MainActor
    public func setAutoUpdateLastCheckTime(_ value: Int64) async {
        await updateData { $0.autoUpdate.lastCheckTime = value }
    }

    /// Last successful auto-update time (Unix timestamp)
    public var autoUpdateLastSuccessfulTime: Int64 {
        appData.autoUpdate.lastSuccessfulTime
    }

    @MainActor
    public func setAutoUpdateLastSuccessfulTime(_ value: Int64) async {
        await updateData { $0.autoUpdate.lastSuccessfulTime = value }
    }

    /// Next eligible auto-update time (Unix timestamp)
    public var autoUpdateNextEligibleTime: Int64 {
        appData.autoUpdate.nextEligibleTime
    }

    @MainActor
    public func setAutoUpdateNextEligibleTime(_ value: Int64) async {
        await updateData { $0.autoUpdate.nextEligibleTime = value }
    }

    /// Force next auto-update
    public var autoUpdateForceNext: Bool {
        appData.autoUpdate.forceNext
    }

    @MainActor
    public func setAutoUpdateForceNext(_ value: Bool) async {
        await updateData { $0.autoUpdate.forceNext = value }
    }

    /// Indicates if auto-update is currently running
    public var autoUpdateIsRunning: Bool {
        appData.autoUpdate.isRunning
    }

    @MainActor
    public func setAutoUpdateIsRunning(_ value: Bool) async {
        let nowTimestamp = Int64(Date().timeIntervalSince1970)
        await updateDataImmediately { data in
            // When the flag isn't actually changing, only refresh the heartbeat timestamp.
            guard data.autoUpdate.isRunning != value else {
                if value {
                    data.autoUpdate.runningSinceTimestamp = nowTimestamp
                } else {
                    data.autoUpdate.runningSinceTimestamp = 0
                }
                return
            }
            data.autoUpdate.isRunning = value
            data.autoUpdate.runningSinceTimestamp = value ? nowTimestamp : 0
        }
    }

    /// Refreshes the running timestamp without re-writing unrelated auto-update fields.
    /// Used by heartbeat paths to avoid heavier state mutations.
    @MainActor
    public func refreshAutoUpdateRunningTimestamp(minimumIntervalSeconds: Int64 = 45) async {
        guard appData.autoUpdate.isRunning else { return }
        let nowTimestamp = Int64(Date().timeIntervalSince1970)
        let previous = appData.autoUpdate.runningSinceTimestamp
        guard previous == 0 || (nowTimestamp - previous) >= minimumIntervalSeconds else { return }
        await updateDataImmediately { $0.autoUpdate.runningSinceTimestamp = nowTimestamp }
    }

    /// Timestamp when auto-update started running
    public var autoUpdateRunningSinceTimestamp: Int64 {
        appData.autoUpdate.runningSinceTimestamp
    }

    /// Get ETag for a specific filter UUID
    public func getFilterEtag(_ uuid: String) -> String? {
        appData.autoUpdate.filterEtags[uuid]
    }

    @MainActor
    public func setFilterEtag(_ uuid: String, etag: String?) async {
        await setFilterValidators(uuid, etag: etag, lastModified: nil, updateLastModified: false)
    }

    /// Get Last-Modified header for a specific filter UUID
    public func getFilterLastModified(_ uuid: String) -> String? {
        appData.autoUpdate.filterLastModified[uuid]
    }

    @MainActor
    public func setFilterLastModified(_ uuid: String, lastModified: String?) async {
        await setFilterValidators(uuid, etag: nil, lastModified: lastModified, updateETag: false)
    }

    /// Sets both ETag and Last-Modified validators for a filter in a single write.
    @MainActor
    public func setFilterValidators(_ uuid: String, etag: String?, lastModified: String?) async {
        await setFilterValidators(uuid, etag: etag, lastModified: lastModified, updateETag: true, updateLastModified: true)
    }

    /// Batch-updates validators for multiple filters with one persisted write.
    @MainActor
    public func setFilterValidators(_ updates: [String: (etag: String?, lastModified: String?)]) async {
        guard !updates.isEmpty else { return }
        await updateDataImmediately { data in
            for (uuid, update) in updates {
                if let etag = update.etag {
                    data.autoUpdate.filterEtags[uuid] = etag
                } else {
                    data.autoUpdate.filterEtags.removeValue(forKey: uuid)
                }

                if let lastModified = update.lastModified {
                    data.autoUpdate.filterLastModified[uuid] = lastModified
                } else {
                    data.autoUpdate.filterLastModified.removeValue(forKey: uuid)
                }
            }
        }
    }

    @MainActor
    private func setFilterValidators(
        _ uuid: String,
        etag: String?,
        lastModified: String?,
        updateETag: Bool = true,
        updateLastModified: Bool = true
    ) async {
        await updateDataImmediately { data in
            if updateETag {
                if let etag = etag {
                    data.autoUpdate.filterEtags[uuid] = etag
                } else {
                    data.autoUpdate.filterEtags.removeValue(forKey: uuid)
                }
            }
            if updateLastModified {
                if let lastModified = lastModified {
                    data.autoUpdate.filterLastModified[uuid] = lastModified
                } else {
                    data.autoUpdate.filterLastModified.removeValue(forKey: uuid)
                }
            }
        }
    }

    public var autoUpdateDiagnostics: AutoUpdateDiagnosticsSnapshot {
        AutoUpdateDiagnosticsSnapshot(
            bgAppRefresh: backgroundTaskDiagnosticsSnapshot(from: appData.autoUpdate.bgAppRefresh),
            bgProcessing: backgroundTaskDiagnosticsSnapshot(from: appData.autoUpdate.bgProcessing),
            lastForegroundCatchUpTime: appData.autoUpdate.lastForegroundCatchUpTime,
            lastForegroundCatchUpReason: appData.autoUpdate.lastForegroundCatchUpReason
        )
    }

    @MainActor
    public func recordAutoUpdateTaskScheduleAttempt(
        _ kind: AutoUpdateDiagnosticTaskKind,
        result: AutoUpdateDiagnosticResult,
        error: String? = nil
    ) async {
        let timestamp = Self.currentUnixTimestamp()
        await updateBackgroundTaskDiagnostics(kind) { diagnostics in
            diagnostics.lastScheduleAttemptTime = timestamp
            diagnostics.lastScheduleResult = result.rawValue
            diagnostics.lastScheduleError = error ?? ""
        }
    }

    @MainActor
    public func recordAutoUpdateTaskStart(_ kind: AutoUpdateDiagnosticTaskKind) async {
        let timestamp = Self.currentUnixTimestamp()
        await updateBackgroundTaskDiagnostics(kind) { diagnostics in
            diagnostics.lastStartTime = timestamp
        }
    }

    @MainActor
    public func recordAutoUpdateTaskCompletion(
        _ kind: AutoUpdateDiagnosticTaskKind,
        result: AutoUpdateDiagnosticResult
    ) async {
        let timestamp = Self.currentUnixTimestamp()
        await updateBackgroundTaskDiagnostics(kind) { diagnostics in
            diagnostics.lastCompletionTime = timestamp
            diagnostics.lastCompletionResult = result.rawValue
        }
    }

    @MainActor
    public func recordAutoUpdateTaskExpiration(_ kind: AutoUpdateDiagnosticTaskKind) async {
        let timestamp = Self.currentUnixTimestamp()
        await updateBackgroundTaskDiagnostics(kind) { diagnostics in
            diagnostics.lastExpirationTime = timestamp
        }
    }

    @MainActor
    public func recordAutoUpdateForegroundCatchUp(reason: AutoUpdateDiagnosticResult) async {
        let timestamp = Self.currentUnixTimestamp()
        await updateData { data in
            data.autoUpdate.lastForegroundCatchUpTime = timestamp
            data.autoUpdate.lastForegroundCatchUpReason = reason.rawValue
        }
    }

    private static func currentUnixTimestamp() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }

    private func backgroundTaskDiagnosticsSnapshot(
        from diagnostics: Wblock_Data_BackgroundTaskDiagnostics
    ) -> BackgroundTaskDiagnosticsSnapshot {
        BackgroundTaskDiagnosticsSnapshot(
            lastScheduleAttemptTime: diagnostics.lastScheduleAttemptTime,
            lastScheduleResult: diagnostics.lastScheduleResult,
            lastScheduleError: diagnostics.lastScheduleError,
            lastStartTime: diagnostics.lastStartTime,
            lastCompletionTime: diagnostics.lastCompletionTime,
            lastCompletionResult: diagnostics.lastCompletionResult,
            lastExpirationTime: diagnostics.lastExpirationTime
        )
    }

    @MainActor
    private func updateBackgroundTaskDiagnostics(
        _ kind: AutoUpdateDiagnosticTaskKind,
        mutate: (inout Wblock_Data_BackgroundTaskDiagnostics) -> Void
    ) async {
        await updateData { data in
            switch kind {
            case .appRefresh:
                mutate(&data.autoUpdate.bgAppRefresh)
            case .processing:
                mutate(&data.autoUpdate.bgProcessing)
            }
        }
    }


    // MARK: - Extension Data (Tab Tracking)

    /// Get blocked count for a specific tab ID
    public func getTabBlockedCount(_ tabId: String) -> Int {
        Int(appData.extensionData.tabBlockedRequests[tabId]?.blockedCount ?? 0)
    }

    /// Get host for a specific tab ID
    public func getTabHost(_ tabId: String) -> String {
        appData.extensionData.tabBlockedRequests[tabId]?.host ?? ""
    }

    /// Check if a tab is disabled
    public func isTabDisabled(_ tabId: String) -> Bool {
        appData.extensionData.tabBlockedRequests[tabId]?.isDisabled ?? false
    }

    @MainActor
    public func setTabDisabled(_ tabId: String, isDisabled: Bool) async {
        await updateDataImmediately { data in
            var tabData = data.extensionData.tabBlockedRequests[tabId] ?? Wblock_Data_TabData()
            tabData.isDisabled = isDisabled
            tabData.lastUpdated = Int64(Date().timeIntervalSince1970)
            data.extensionData.tabBlockedRequests[tabId] = tabData
            data.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    @MainActor
    public func removeTabData(_ tabId: String) async {
        await updateDataImmediately { data in
            data.extensionData.tabBlockedRequests.removeValue(forKey: tabId)
            data.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    @MainActor
    public func updateTabBlockedCount(_ tabId: String, host: String, increment: Int = 1) async {
        await updateDataImmediately { data in
            var tabData = data.extensionData.tabBlockedRequests[tabId] ?? Wblock_Data_TabData()
            tabData.blockedCount += Int32(increment)
            tabData.host = host
            tabData.lastUpdated = Int64(Date().timeIntervalSince1970)
            data.extensionData.tabBlockedRequests[tabId] = tabData
            data.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    @MainActor
    public func clearOldTabData(olderThan: TimeInterval) async {
        let cutoffTime = Int64(Date().timeIntervalSince1970 - olderThan)
        await updateDataImmediately { data in
            data.extensionData.tabBlockedRequests = data.extensionData.tabBlockedRequests.filter { _, tabData in
                tabData.lastUpdated >= cutoffTime
            }
            data.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    /// Get all tab IDs that have data
    public var allTabIds: [String] {
        Array(appData.extensionData.tabBlockedRequests.keys)
    }

    // MARK: - Zapper Rules

    /// Returns sorted array of all hostnames that have at least one zapper rule.
    public func getZapperDomains() -> [String] {
        appData.extensionData.zapperRulesByHost
            .filter { !$0.value.selectors.isEmpty }
            .map { $0.key }
            .sorted()
    }

    /// Returns the selectors array for a given hostname, filtered for non-empty entries.
    public func getZapperRules(forHost host: String) -> [String] {
        guard let ruleList = appData.extensionData.zapperRulesByHost[host] else { return [] }
        return ruleList.selectors.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Sets/replaces rules for a host. If rules are empty, removes the key.
    /// Preserves the host's `disabled` flag so content-script syncs cannot reset it.
    @MainActor
    public func setZapperRules(forHost host: String, rules: [String]) async {
        let filtered = rules.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        await updateDataImmediately { data in
            let existing = data.extensionData.zapperRulesByHost[host]
            if filtered.isEmpty {
                guard existing != nil else { return }
                data.extensionData.zapperRulesByHost.removeValue(forKey: host)
            } else {
                if let existing,
                   existing.selectors == filtered,
                   existing.pendingDeletions.isEmpty {
                    return
                }
                var ruleList = Wblock_Data_ZapperRuleList()
                ruleList.selectors = filtered
                ruleList.disabled = existing?.disabled ?? false
                data.extensionData.zapperRulesByHost[host] = ruleList
            }
            data.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    /// Adds a single selector to the host's list if not already present.
    /// Also clears any matching pending deletion (the user re-created a previously deleted rule).
    @MainActor
    public func addZapperRule(_ selector: String, forHost host: String) async {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await updateDataImmediately { data in
            var ruleList = data.extensionData.zapperRulesByHost[host] ?? Wblock_Data_ZapperRuleList()
            if !ruleList.selectors.contains(trimmed) {
                ruleList.selectors.append(trimmed)
            }
            ruleList.pendingDeletions.removeAll { $0 == trimmed }
            data.extensionData.zapperRulesByHost[host] = ruleList
            data.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    /// Removes a single selector. If the selectors array becomes empty, removes the host key
    /// (but keeps it if there are pending deletions the extension hasn't consumed yet).
    @MainActor
    public func deleteZapperRule(_ selector: String, forHost host: String) async {
        await updateDataImmediately { data in
            var ruleList = data.extensionData.zapperRulesByHost[host] ?? Wblock_Data_ZapperRuleList()
            ruleList.selectors.removeAll { $0 == selector }
            ruleList.pendingDeletions.append(selector)
            if ruleList.selectors.isEmpty && ruleList.pendingDeletions.isEmpty {
                data.extensionData.zapperRulesByHost.removeValue(forKey: host)
            } else {
                data.extensionData.zapperRulesByHost[host] = ruleList
            }
            data.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    /// Removes all selectors for a host and records them as pending deletions
    /// so the extension sync handler can filter them out.
    @MainActor
    public func deleteAllZapperRules(forHost host: String) async {
        await updateDataImmediately { data in
            var ruleList = data.extensionData.zapperRulesByHost[host] ?? Wblock_Data_ZapperRuleList()
            ruleList.pendingDeletions.append(contentsOf: ruleList.selectors)
            ruleList.selectors.removeAll()
            if ruleList.pendingDeletions.isEmpty {
                data.extensionData.zapperRulesByHost.removeValue(forKey: host)
            } else {
                data.extensionData.zapperRulesByHost[host] = ruleList
            }
            data.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    /// Returns and clears pending deletions for a host. Used by the sync handler to
    /// filter out rules deleted from the app before the extension could be notified.
    @MainActor
    public func consumeZapperPendingDeletions(forHost host: String) async -> [String] {
        pendingSaveTask?.cancel()

        do {
            let mutation = try await diskStore.mutateAppDataAtomically(
                at: dataFileURL,
                versionURL: dataVersionFileURL
            ) { data in
                guard var ruleList = data.extensionData.zapperRulesByHost[host],
                      !ruleList.pendingDeletions.isEmpty else {
                    return [String]()
                }

                let deletions = ruleList.pendingDeletions
                ruleList.pendingDeletions.removeAll()

                if ruleList.selectors.isEmpty {
                    data.extensionData.zapperRulesByHost.removeValue(forKey: host)
                } else {
                    data.extensionData.zapperRulesByHost[host] = ruleList
                }
                data.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
                return deletions
            }

            appData = mutation.appData
            lastSavedData = mutation.rawData
            lastLoadedDataFileModificationDate = mutation.modificationDate
            lastLoadedDataVersion = mutation.version
            lastError = nil

            if mutation.didWrite {
                logger.info("✅ Saved protobuf data (\(mutation.rawData.count) bytes)")
                didSaveDataSubject.send()
            }

            return mutation.result
        } catch {
            logger.error("❌ Failed to consume pending zapper deletions: \(error.localizedDescription)")
            lastError = error
            return []
        }
    }

    /// Re-inserts a selector at the given index (clamped to bounds).
    @MainActor
    public func restoreZapperRule(_ selector: String, forHost host: String, at index: Int) async {
        await updateDataImmediately { data in
            var ruleList = data.extensionData.zapperRulesByHost[host] ?? Wblock_Data_ZapperRuleList()
            let insertIndex = min(max(index, 0), ruleList.selectors.count)
            ruleList.pendingDeletions.removeAll { $0 == selector }
            ruleList.selectors.insert(selector, at: insertIndex)
            data.extensionData.zapperRulesByHost[host] = ruleList
            data.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    /// True when the host's zapper rules are kept but not applied.
    public func isZapperDisabled(forHost host: String) -> Bool {
        appData.extensionData.zapperRulesByHost[host]?.disabled ?? false
    }

    /// Sorted hostnames whose zapper rules are currently disabled.
    public func getDisabledZapperDomains() -> [String] {
        appData.extensionData.zapperRulesByHost
            .filter { $0.value.disabled && !$0.value.selectors.isEmpty }
            .map { $0.key }
            .sorted()
    }

    /// Flips the per-host kill switch. No-op for hosts without rules.
    @MainActor
    public func setZapperRulesDisabled(_ disabled: Bool, forHost host: String) async {
        await updateDataImmediately { data in
            guard var ruleList = data.extensionData.zapperRulesByHost[host],
                  ruleList.disabled != disabled else { return }
            ruleList.disabled = disabled
            data.extensionData.zapperRulesByHost[host] = ruleList
            data.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        }
    }

    /// Rules per host with disabled hosts and empty selectors filtered out.
    /// This is the only input rule generation should use.
    public func getActiveZapperRulesByHost() -> [String: [String]] {
        appData.extensionData.zapperRulesByHost.compactMapValues { ruleList in
            guard !ruleList.disabled else { return nil }
            let selectors = ruleList.selectors.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return selectors.isEmpty ? nil : selectors
        }
    }

    // MARK: - Per-Site Userscript Exceptions

    /// Map of script UUID string -> hosts where that script is disabled.
    public func getUserScriptDisabledHosts() -> [String: [String]] {
        appData.userScriptDisabledHosts.mapValues { $0.hosts }
    }

    /// Hosts where the given script is disabled.
    public func getUserScriptDisabledHosts(forScriptID id: String) -> [String] {
        appData.userScriptDisabledHosts[id]?.hosts ?? []
    }

    /// Replaces the disabled-host list for one script; empty list removes the entry.
    @MainActor
    public func setUserScriptDisabledHosts(_ hosts: [String], forScriptID id: String) async {
        guard getUserScriptDisabledHosts(forScriptID: id) != hosts else { return }
        let changed = await updateDataImmediately { data in
            if hosts.isEmpty {
                data.userScriptDisabledHosts.removeValue(forKey: id)
            } else {
                var list = Wblock_Data_HostList()
                list.hosts = hosts
                data.userScriptDisabledHosts[id] = list
            }
        }
        if changed {
            UserScriptManager.invalidateDocumentStartExecutionCache()
        }
    }

    /// Replaces the whole exceptions map (backup restore / cloud sync / migration).
    @MainActor
    public func setAllUserScriptDisabledHosts(_ map: [String: [String]]) async {
        let desired = map.filter { !$0.value.isEmpty }
        guard getUserScriptDisabledHosts() != desired else { return }
        let changed = await updateDataImmediately { data in
            data.userScriptDisabledHosts.removeAll()
            for (id, hosts) in desired {
                var list = Wblock_Data_HostList()
                list.hosts = hosts
                data.userScriptDisabledHosts[id] = list
            }
        }
        if changed {
            UserScriptManager.invalidateDocumentStartExecutionCache()
        }
    }

    // MARK: - Singleton
    public static let shared = ProtobufDataManager()
    
    // MARK: - Published Properties
    @Published var appData = Wblock_Data_AppData()
    
    var publicAppData: Wblock_Data_AppData {
        appData
    }
    @Published public private(set) var isLoading = true
    @Published public private(set) var lastError: Error?

    private let didSaveDataSubject = PassthroughSubject<Void, Never>()
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.skula.wBlock", category: "ProtobufDataManager")
    private let fileManager = FileManager.default
    private let diskStore = ProtobufDiskStore()
    private let dataFileName = "wblock_data.pb"
    private let backupFileName = "wblock_data_backup.pb"
    private let dataVersionFileName = "wblock_data.version"
    private let migrationFileName = "migration_completed.flag"
    private let terminologySanitizationVersion = 1 // Increment this to re-run sanitization
    private var lastLoadedDataFileModificationDate: Date?
    private var lastLoadedDataVersion: Int64 = 0
    private var initialLoadTask: Task<Void, Never>?
    /// Incremented before reset starts. Every asynchronous writer validates this token both
    /// before disk I/O and before publishing its result.
    private var storageGeneration: UInt64 = 0

    /// Returns the most recent app data snapshot from disk if available; otherwise, returns the in-memory value.
    /// This helps avoid clobbering concurrent writes from other processes that share the app group file.
    func latestAppDataSnapshot(forceReadFromDisk: Bool = false) async -> Wblock_Data_AppData {
        let currentModDate = await diskStore.modificationDate(for: dataFileURL)
        let currentVersion = await diskStore.dataVersion(for: dataVersionFileURL)

        // If nothing changed on disk, avoid redundant decode work.
        if !forceReadFromDisk,
            let currentModDate,
            currentModDate == lastLoadedDataFileModificationDate,
            currentVersion == lastLoadedDataVersion
        {
            return appData
        }

        // Try to read the persisted file first to incorporate recent writes from extensions or helper processes.
        if await diskStore.fileExists(at: dataFileURL),
           let loaded = try? await diskStore.readAppData(from: dataFileURL) {
            lastLoadedDataFileModificationDate = loaded.modificationDate ?? currentModDate
            lastSavedData = loaded.rawData
            lastLoadedDataVersion = currentVersion
            return loaded.appData
        }

        // Fallback to current in-memory state if file is missing or unreadable.
        return appData
    }

    /// Reloads protobuf data from disk only if the underlying file has changed.
    /// Returns `true` when in-memory state was refreshed.
    @discardableResult
    public func refreshFromDiskIfModified(forceRead: Bool = false) async -> Bool {
        guard let currentModDate = await diskStore.modificationDate(for: dataFileURL) else {
            return false
        }
        let currentVersion = await diskStore.dataVersion(for: dataVersionFileURL)
        if !forceRead,
            let lastLoaded = lastLoadedDataFileModificationDate,
            lastLoaded == currentModDate,
            currentVersion == lastLoadedDataVersion
        {
            return false
        }

        do {
            let loaded = try await diskStore.readAppData(from: dataFileURL)
            let didChange = lastSavedData != loaded.rawData
            if didChange {
                appData = loaded.appData
            }
            lastSavedData = loaded.rawData
            lastLoadedDataFileModificationDate = loaded.modificationDate ?? currentModDate
            lastLoadedDataVersion = currentVersion
            lastError = nil
            return didChange
        } catch {
            lastError = error
            logger.error("❌ Failed to refresh protobuf data from disk: \(error.localizedDescription)")
            return false
        }
    }
    
    // File URLs
    private lazy var dataFileURL: URL = {
        getDataDirectoryURL().appendingPathComponent(dataFileName)
    }()
    
    private lazy var backupFileURL: URL = {
        getDataDirectoryURL().appendingPathComponent(backupFileName)
    }()

    private lazy var dataVersionFileURL: URL = {
        getDataDirectoryURL().appendingPathComponent(dataVersionFileName)
    }()
    
    private lazy var migrationFlagURL: URL = {
        getDataDirectoryURL().appendingPathComponent(migrationFileName)
    }()
    
    // MARK: - Initialization
    private init() {
        logger.info("🔧 ProtobufDataManager initializing...")
        setupDataDirectory()
        var task: Task<Void, Never>?
        task = Task { @MainActor [weak self] in
            defer {
                if let self, let task, self.initialLoadTask == task {
                    self.initialLoadTask = nil
                }
            }
            await self?.loadData()
        }
        initialLoadTask = task
    }

    /// Waits for the initial protobuf load to complete.
    public func waitUntilLoaded() async {
        if let task = initialLoadTask {
            await task.value
            return
        }

        // Fallback (shouldn't happen): suspend until initial load flips `isLoading`.
        while isLoading {
            await Task.yield()
        }
    }

    // MARK: - Helper Methods

    /// Generic helper method to reduce boilerplate in setter methods
    /// Updates appData using a closure and saves the changes
    @MainActor
    private func updateData(with block: (inout Wblock_Data_AppData) -> Void) async {
        var updatedData = await latestAppDataSnapshot()
        block(&updatedData)
        appData = updatedData
        saveData()
    }

    /// Writes immediately for cross-process paths that need deterministic visibility.
    @MainActor
    @discardableResult
    func updateDataImmediately(
        userScriptsAreAuthoritative: Bool = false,
        explicitlyDeletedFilterIDs: Set<String> = [],
        with block: @escaping @Sendable (inout Wblock_Data_AppData) -> Void
    ) async -> Bool {
        pendingSaveTask?.cancel()
        let writeGeneration = storageGeneration
        let pendingSnapshot = appData
        let pendingRawData = try? pendingSnapshot.serializedData()
        let pendingBaseline = lastSavedData

        do {
            guard writeGeneration == storageGeneration else { return false }
            let mutation = try await diskStore.mutateAppDataAtomically(
                at: dataFileURL,
                versionURL: dataVersionFileURL,
                mutate: block
            )
            guard writeGeneration == storageGeneration else { return false }
            var finalAppData = mutation.appData
            var finalRawData = mutation.rawData
            var finalModificationDate = mutation.modificationDate
            var finalVersion = mutation.version
            var didWrite = mutation.didWrite

            // The immediate mutation read the disk snapshot, but the actor may also
            // have unsaved in-memory changes in another field. Rebase those changes
            // over the mutation and persist the combined result instead of dropping
            // them when appData is replaced below.
            if let pendingRawData,
               let pendingBaseline,
               pendingRawData != pendingBaseline,
               let previousSnapshot = try? Wblock_Data_AppData(serializedBytes: pendingBaseline) {
                var rebased = pendingSnapshot
                mergePersistedChanges(
                    in: &rebased,
                    comparedTo: previousSnapshot,
                    from: mutation.appData,
                    explicitlyDeletedFilterIDs: explicitlyDeletedFilterIDs
                )
                if userScriptsAreAuthoritative {
                    // Replacement/removal already carries the manager’s complete collection.
                    // Preserve pending host changes only for scripts that still exist.
                    rebased.userScripts = mutation.appData.userScripts
                    let survivingIDs = Set(rebased.userScripts.map(\.id))
                    rebased.userScriptDisabledHosts = rebased.userScriptDisabledHosts.filter {
                        survivingIDs.contains($0.key)
                    }
                }
                if let result = try await diskStore.writeAppDataIfChanged(
                    appData: rebased,
                    previousData: mutation.rawData,
                    explicitlyDeletedFilterIDs: explicitlyDeletedFilterIDs,
                    to: dataFileURL,
                    versionURL: dataVersionFileURL
                ) {
                    finalAppData = result.appData
                    finalRawData = result.rawData
                    finalModificationDate = result.modificationDate
                    finalVersion = result.version
                    didWrite = didWrite || result.didWrite
                }
            }

            guard writeGeneration == storageGeneration else { return false }
            appData = finalAppData
            lastSavedData = finalRawData
            lastLoadedDataFileModificationDate = finalModificationDate
            lastLoadedDataVersion = finalVersion
            lastError = nil

            if didWrite {
                logger.info("✅ Saved protobuf data (\(finalRawData.count) bytes)")
                didSaveDataSubject.send()
            }
            return true
        } catch {
            logger.error("❌ Failed to save data immediately: \(error.localizedDescription)")
            lastError = error
            return false
        }
    }
    
    // MARK: - Data Directory Setup
    private func setupDataDirectory() {
        let dataDir = getDataDirectoryURL()
        if !fileManager.fileExists(atPath: dataDir.path) {
            do {
                try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)
                logger.info("✅ Created data directory: \(dataDir.path)")
            } catch {
                logger.error("❌ Failed to create data directory: \(error)")
            }
        }
    }

    /// Returns the protobuf data directory in the shared app group container.
    /// Exposed for filesystem observation in clients that need cross-process change detection.
    public func protobufDataDirectoryURL() -> URL? {
        getDataDirectoryURL()
    }
    
    private func getDataDirectoryURL() -> URL {
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) {
            return containerURL.appendingPathComponent("ProtobufData")
        } else {
            // Fallback to app support directory
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            return appSupport.appendingPathComponent("wBlock").appendingPathComponent("ProtobufData")
        }
    }

    // MARK: - Legacy Migration Sanitization

    private static let defaultAutoUpdateIntervalHours: Double = 6.0
    private static let minimumAutoUpdateIntervalHours: Double = 1.0
    private static let maximumAutoUpdateIntervalHours: Double = 24.0 * 7.0

    private static func sanitizeAutoUpdateIntervalHours(_ value: Double) -> Double {
        guard value.isFinite else { return defaultAutoUpdateIntervalHours }
        guard value > 0 else { return defaultAutoUpdateIntervalHours }
        return min(max(value, minimumAutoUpdateIntervalHours), maximumAutoUpdateIntervalHours)
    }

    private static func sanitizeEpochSecondsToInt64(_ value: Double) -> Int64 {
        guard value.isFinite else { return 0 }
        guard value > 0 else { return 0 }
        if value >= Double(Int64.max) { return Int64.max }
        return Int64(value)
    }
    
    // MARK: - Data Loading
    public func loadData() async {
        isLoading = true
        
        do {
            // Check if migration is needed
            if !(await diskStore.fileExists(at: migrationFlagURL)) {
                logger.info("🔄 Starting migration from UserDefaults/SwiftData...")
                await migrateFromLegacyStorage()
                try await diskStore.writeData(Data(), to: migrationFlagURL)
                logger.info("✅ Migration completed")
            }
            
            // Load protobuf data
            if await diskStore.fileExists(at: dataFileURL) {
                let loaded = try await diskStore.readAppData(from: dataFileURL)
                let dataVersion = await diskStore.dataVersion(for: dataVersionFileURL)

                appData = loaded.appData
                lastSavedData = loaded.rawData
                lastLoadedDataFileModificationDate = loaded.modificationDate
                lastLoadedDataVersion = dataVersion
                lastError = nil

                logger.info("✅ Loaded protobuf data (\(loaded.rawData.count) bytes)")

                // Migrate BPC userscript from gitflic to Greasy Fork
                var needsSave = false
                let oldBpcURL = "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=userscript%2Fbpc.en.user.js"
                let newBpcURL = "https://greasyfork.org/scripts/542351-bypass-paywalls-clean-en/code/Bypass%20Paywalls%20Clean%20(EN).user.js"
                if let bpcIndex = appData.userScripts.firstIndex(where: { $0.url == oldBpcURL }) {
                    appData.userScripts[bpcIndex].url = newBpcURL
                    logger.info("🔄 Migrated BPC userscript URL from gitflic to Greasy Fork")
                    needsSave = true
                }

                // Migrate BPC filter list from gitflic to Cloudflare proxy
                let oldBpcFilterURL = "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=bpc-paywall-filter.txt"
                let newBpcFilterURL = "https://bpc-filter-proxy.wmailrelayb8d890.workers.dev"
                if let bpcFilterIndex = appData.filterLists.firstIndex(where: { $0.url == oldBpcFilterURL }) {
                    appData.filterLists[bpcFilterIndex].url = newBpcFilterURL
                    logger.info("🔄 Migrated BPC filter list URL from gitflic to Cloudflare proxy")
                    needsSave = true
                }

                if needsSave {
                    await saveDataImmediately()
                }

                // Check if terminology sanitization is needed
                if appData.settings.lastTerminologySanitizationVersion < terminologySanitizationVersion {
                    logger.info("🧹 Running terminology sanitization (version \(self.terminologySanitizationVersion))...")
                    await sanitizeStoredTerminology()
                }
            } else {
                logger.info("📝 No existing data file, creating default data")
                await createDefaultData()
            }
            
        } catch {
            logger.error("❌ Failed to load data: \(error)")
            lastError = error
            
            // Try to load backup
            await loadBackup()
        }
        
        isLoading = false
    }
    
    private func loadBackup() async {
        guard await diskStore.fileExists(at: backupFileURL) else {
            logger.info("📝 No backup file available, creating default data")
            await createDefaultData()
            return
        }
        
        do {
            let loaded = try await diskStore.readAppData(from: backupFileURL)

            appData = loaded.appData
            lastSavedData = loaded.rawData
            lastLoadedDataVersion = await diskStore.dataVersion(for: dataVersionFileURL)
            lastError = nil

            logger.info("✅ Loaded backup data (\(loaded.rawData.count) bytes)")
        } catch {
            logger.error("❌ Failed to load backup: \(error)")
            await createDefaultData()
        }
    }
    
    @MainActor
    @discardableResult
    public func resetToDefaultData(preservingOnboardingCompletion: Bool = false) async -> Bool {
        logger.info("🔄 Resetting protobuf data to default state")
        storageGeneration &+= 1
        let resetGeneration = storageGeneration
        pendingSaveTask?.cancel()

        do {
            try await diskStore.resetFiles(dataURL: dataFileURL, backupURL: backupFileURL, versionURL: dataVersionFileURL)
        } catch {
            lastError = error
            logger.error("⚠️ Failed to reset protobuf storage: \(error.localizedDescription)")
            return false
        }
        guard storageGeneration == resetGeneration else { return false }
        lastSavedData = nil
        lastLoadedDataFileModificationDate = nil
        lastLoadedDataVersion = 0
        let storageResetResult = await UserScriptStorageManager.shared.reset()
        guard storageGeneration == resetGeneration else { return false }
        let storageResetError = storageResetResult.ok
            ? nil
            : NSError(
                domain: "ProtobufDataManager",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        storageResetResult.error ?? "Failed to reset userscript storage"
                ]
            )
        if let storageResetError {
            logger.error(
                "⚠️ Failed to reset userscript storage during reset: \(storageResetError.localizedDescription)")
        }

        let createdDefaults = await createDefaultData(
            hasCompletedOnboarding: preservingOnboardingCompletion
        )
        if let storageResetError { lastError = storageResetError }
        return storageGeneration == resetGeneration && createdDefaults && storageResetError == nil
    }

    @discardableResult
    private func createDefaultData(hasCompletedOnboarding: Bool = false) async -> Bool {
        var defaultData = Wblock_Data_AppData()

        // Initialize default settings
        defaultData.settings.hasCompletedOnboarding_p = hasCompletedOnboarding
        defaultData.settings.selectedBlockingLevel = "recommended"
        defaultData.settings.lastUpdateCheck = Int64(Date().timeIntervalSince1970)
        defaultData.settings.showAdvancedFeatures = false
        defaultData.settings.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        defaultData.settings.isBadgeCounterEnabled = true

        // Initialize default auto-update settings
        defaultData.autoUpdate.enabled = true
        defaultData.autoUpdate.intervalHours = 6.0
        defaultData.autoUpdate.lastCheckTime = 0
        defaultData.autoUpdate.lastSuccessfulTime = 0
        defaultData.autoUpdate.nextEligibleTime = 0
        defaultData.autoUpdate.forceNext = false
        defaultData.autoUpdate.isRunning = false
        defaultData.autoUpdate.runningSinceTimestamp = 0

        // Initialize default performance data
        #if os(macOS)
        defaultData.performance.currentPlatform = .macos
        #else
        defaultData.performance.currentPlatform = .ios
        #endif

        defaultData.performance.lastConversionTime = "N/A"
        defaultData.performance.lastReloadTime = "N/A"
        defaultData.performance.lastFastUpdateTime = "N/A"

        appData = defaultData
        let saved = await saveDataImmediately()
        if saved {
            logger.info("✅ Created default data")
        } else {
            logger.error("❌ Failed to persist default data")
        }
        return saved
    }
    
    // MARK: - Data Saving (debounced)
    private var pendingSaveTask: Task<Void, Never>?
    private let saveDebounceDelay: AsyncDelay = .milliseconds(500)
    private var lastSavedData: Data?

    public func saveData() {
        pendingSaveTask?.cancel()
        let delay = saveDebounceDelay
        var task: Task<Void, Never>?
        task = Task { @MainActor [weak self] in
            defer {
                if let self, let task, self.pendingSaveTask == task {
                    self.pendingSaveTask = nil
                }
            }
            do {
                try await TaskSleep.sleep(for: delay)
            } catch {
                return
            }
            guard let self else { return }
            await self.performSaveData()
        }
        pendingSaveTask = task
    }

    /// Saves data immediately without debounce delay
    /// Use when changes must be persisted before other cross-process actions
    @MainActor
    @discardableResult
    public func saveDataImmediately() async -> Bool {
        pendingSaveTask?.cancel()
        return await performSaveData()
    }

    @discardableResult
    private func performSaveData() async -> Bool {
        let writeGeneration = storageGeneration
        let snapshot = appData
        let snapshotRawData = try? snapshot.serializedData()
        let previous = lastSavedData

        guard writeGeneration == storageGeneration else { return false }
        do {
            if let result = try await diskStore.writeAppDataIfChanged(
                appData: snapshot,
                previousData: previous,
                to: dataFileURL,
                versionURL: dataVersionFileURL
            ) {
                guard writeGeneration == storageGeneration else { return false }
                if (try? appData.serializedData()) == snapshotRawData {
                    appData = result.appData
                } else {
                    mergePersistedChanges(
                        in: &appData,
                        comparedTo: snapshot,
                        from: result.appData
                    )
                }
                lastSavedData = result.rawData
                lastLoadedDataFileModificationDate = result.modificationDate
                lastLoadedDataVersion = result.version
                lastError = nil
                if result.didWrite {
                    logger.info("✅ Saved protobuf data (\(result.rawData.count) bytes)")
                    didSaveDataSubject.send()
                }
            }
            return true
        } catch {
            logger.error("❌ Failed to save data: \(error)")
            lastError = error
            return false
        }
    }
    
    // MARK: - Terminology Sanitization

    // Pre-compiled regex patterns for efficiency (compiled once, reused many times)
    private static let sanitizationRegexes: [(regex: NSRegularExpression, replacement: String)] = {
        let patterns: [(pattern: String, replacement: String)] = [
            ("malicious", "suspicious"),
            ("malware", "unwanted software"),
            ("spyware", "tracking software"),
            ("harmful", "unwanted"),
            ("dangerous", "risky")
        ]

        return patterns.compactMap { pattern, replacement in
            guard let regex = try? NSRegularExpression(
                pattern: "\\b\(pattern)\\b",
                options: [.caseInsensitive]
            ) else { return nil }
            return (regex, replacement)
        }
    }()

    /// Efficiently sanitizes stored filter list names and descriptions to remove Apple-flagged terminology
    private func sanitizeStoredTerminology() async {
        let startTime = Date()

        // Work directly on MainActor to avoid full copy
        await MainActor.run {
            var modifiedCount = 0

            // Sanitize filter list names AND descriptions
            for index in appData.filterLists.indices {
                // Sanitize name/title
                let originalName = appData.filterLists[index].name
                let sanitizedName = sanitizeText(originalName)
                if sanitizedName != originalName {
                    appData.filterLists[index].name = sanitizedName
                    modifiedCount += 1
                }

                // Sanitize description
                let originalDescription = appData.filterLists[index].description_p
                let sanitizedDescription = sanitizeText(originalDescription)
                if sanitizedDescription != originalDescription {
                    appData.filterLists[index].description_p = sanitizedDescription
                    modifiedCount += 1
                }
            }

            // Sanitize userscript names AND descriptions
            for index in appData.userScripts.indices {
                // Sanitize name/title
                let originalName = appData.userScripts[index].name
                let sanitizedName = sanitizeText(originalName)
                if sanitizedName != originalName {
                    appData.userScripts[index].name = sanitizedName
                    modifiedCount += 1
                }

                // Sanitize description
                let originalDescription = appData.userScripts[index].description_p
                let sanitizedDescription = sanitizeText(originalDescription)
                if sanitizedDescription != originalDescription {
                    appData.userScripts[index].description_p = sanitizedDescription
                    modifiedCount += 1
                }
            }

            // Update sanitization version
            appData.settings.lastTerminologySanitizationVersion = Int32(terminologySanitizationVersion)

            let duration = Date().timeIntervalSince(startTime)
            logger.info("✅ Terminology sanitization completed in \(String(format: "%.2f", duration))s (\(modifiedCount) items updated)")
        }

        // Save once after all modifications
        await saveDataImmediately()
    }

    /// Sanitizes text by replacing Apple-flagged terminology using pre-compiled regexes
    private func sanitizeText(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var sanitized = text
        for (regex, replacement) in Self.sanitizationRegexes {
            let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
            sanitized = regex.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: range,
                withTemplate: replacement
            )
        }

        return sanitized
    }

    // MARK: - Migration from Legacy Storage
    private func migrateFromLegacyStorage() async {
        logger.info("🔄 Migrating from UserDefaults and SwiftData...")

        let groupDefaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
        var migratedData = Wblock_Data_AppData()

        // Migrate app settings
        migratedData.settings.hasCompletedOnboarding_p = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        migratedData.settings.selectedBlockingLevel = UserDefaults.standard.string(forKey: "selectedBlockingLevel") ?? "recommended"

        // Migrate badge counter setting (from App Group UserDefaults)
        if groupDefaults.object(forKey: "isBadgeCounterEnabled") != nil {
            migratedData.settings.isBadgeCounterEnabled = groupDefaults.bool(forKey: "isBadgeCounterEnabled")
        } else {
            migratedData.settings.isBadgeCounterEnabled = true  // Default to enabled
        }

        // Migrate auto-update settings (from App Group UserDefaults)
        if groupDefaults.object(forKey: "autoUpdateEnabled") != nil {
            migratedData.autoUpdate.enabled = groupDefaults.bool(forKey: "autoUpdateEnabled")
        } else {
            migratedData.autoUpdate.enabled = true  // Default to enabled
        }

        migratedData.autoUpdate.intervalHours = Self.sanitizeAutoUpdateIntervalHours(
            groupDefaults.object(forKey: "autoUpdateIntervalHours") as? Double
                ?? Self.defaultAutoUpdateIntervalHours
        )
        migratedData.autoUpdate.lastCheckTime = Self.sanitizeEpochSecondsToInt64(
            groupDefaults.double(forKey: "autoUpdateLastCheckTime")
        )
        migratedData.autoUpdate.lastSuccessfulTime = Self.sanitizeEpochSecondsToInt64(
            groupDefaults.double(forKey: "autoUpdateLastSuccessful")
        )
        migratedData.autoUpdate.nextEligibleTime = Self.sanitizeEpochSecondsToInt64(
            groupDefaults.double(forKey: "autoUpdateNextEligibleTime")
        )
        migratedData.autoUpdate.forceNext = groupDefaults.bool(forKey: "autoUpdateForceNext")
        migratedData.autoUpdate.isRunning = groupDefaults.bool(forKey: "autoUpdateIsRunning")
        migratedData.autoUpdate.runningSinceTimestamp = Self.sanitizeEpochSecondsToInt64(
            groupDefaults.double(forKey: "autoUpdateIsRunningTimestamp")
        )

        // Migrate filter ETags and Last-Modified headers
        // Scan through all keys looking for filterEtag_ and filterLastModified_ prefixes
        for key in groupDefaults.dictionaryRepresentation().keys {
            if key.hasPrefix("filterEtag_") {
                let uuid = String(key.dropFirst("filterEtag_".count))
                if let etag = groupDefaults.string(forKey: key) {
                    migratedData.autoUpdate.filterEtags[uuid] = etag
                }
            } else if key.hasPrefix("filterLastModified_") {
                let uuid = String(key.dropFirst("filterLastModified_".count))
                if let lastModified = groupDefaults.string(forKey: key) {
                    migratedData.autoUpdate.filterLastModified[uuid] = lastModified
                }
            }
        }

        // Migrate tab blocked requests (from App Group UserDefaults)
        if let tabDataJSON = groupDefaults.data(forKey: "tabBlockedRequests"),
           let tabDataDict = try? JSONDecoder().decode([String: LegacyTabData].self, from: tabDataJSON) {
            for (tabId, legacyTab) in tabDataDict {
                var tabData = Wblock_Data_TabData()
                tabData.blockedCount = Int32(legacyTab.blockedCount)
                tabData.isDisabled = legacyTab.isDisabled
                tabData.host = legacyTab.host
                tabData.lastUpdated = Int64(Date().timeIntervalSince1970)
                migratedData.extensionData.tabBlockedRequests[tabId] = tabData
            }
            migratedData.extensionData.lastUpdated = Int64(Date().timeIntervalSince1970)
        }

        // Migrate zapper rules from UserDefaults
        for key in groupDefaults.dictionaryRepresentation().keys {
            if key.hasPrefix("zapperRules_") {
                let hostname = String(key.dropFirst("zapperRules_".count))
                if let rules = groupDefaults.stringArray(forKey: key) {
                    let filtered = rules.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                    if !filtered.isEmpty {
                        var ruleList = Wblock_Data_ZapperRuleList()
                        ruleList.selectors = filtered
                        migratedData.extensionData.zapperRulesByHost[hostname] = ruleList
                    }
                }
            }
        }

        // Migrate filter lists
        await migrateFilterLists(from: groupDefaults, to: &migratedData)

        // Migrate userscripts
        await migrateUserScripts(from: groupDefaults, to: &migratedData)

        // Migrate whitelist data
        migratedData.whitelist.disabledSites = groupDefaults.stringArray(forKey: "disabledSites") ?? []
        migratedData.whitelist.lastUpdated = Int64(Date().timeIntervalSince1970)

        // Migrate rule counts
        migratedData.ruleCounts.lastRuleCount = Int32(groupDefaults.integer(forKey: "lastRuleCount"))

        if let ruleCountsData = groupDefaults.data(forKey: "ruleCountsByCategory"),
           let ruleCounts = try? JSONDecoder().decode([String: Int].self, from: ruleCountsData) {
            for (category, count) in ruleCounts {
                migratedData.ruleCounts.ruleCountsByCategory[category] = Int32(count)
            }
        }

        if let categoriesData = groupDefaults.data(forKey: "categoriesApproachingLimit"),
           let categories = try? JSONDecoder().decode([String].self, from: categoriesData) {
            migratedData.ruleCounts.categoriesApproachingLimit = categories
        }

        await MainActor.run {
            self.appData = migratedData
        }

        saveData()
        logger.info("✅ Migration completed successfully")
    }
    
    private func migrateFilterLists(from userDefaults: UserDefaults, to appData: inout Wblock_Data_AppData) async {
        // Migrate main filter lists
        if let data = userDefaults.data(forKey: "filterLists"),
           let filterLists = try? JSONDecoder().decode([LegacyFilterList].self, from: data) {
            
            for filterList in filterLists {
                let inferredIsCustom = inferLegacyCustomStatus(for: filterList)

                var protoFilterList = Wblock_Data_FilterListData()
                protoFilterList.id = filterList.id.uuidString
                protoFilterList.name = filterList.name
                protoFilterList.url = filterList.url.absoluteString
                protoFilterList.category = mapFilterListCategory(filterList.category)
                protoFilterList.isSelected = filterList.isSelected
                protoFilterList.description_p = filterList.description
                protoFilterList.version = filterList.version
                if let sourceRuleCount = filterList.sourceRuleCount {
                    protoFilterList.sourceRuleCount = Int32(sourceRuleCount)
                }
                protoFilterList.lastUpdated = Int64(Date().timeIntervalSince1970)
                protoFilterList.isCustom = inferredIsCustom

                appendOrMergeMigratedFilterList(protoFilterList, to: &appData)
            }
        }
        
        // Migrate custom filter lists
        if let data = userDefaults.data(forKey: "customFilterLists"),
           let customFilterLists = try? JSONDecoder().decode([LegacyFilterList].self, from: data) {
            
            for filterList in customFilterLists {
                var protoFilterList = Wblock_Data_FilterListData()
                protoFilterList.id = filterList.id.uuidString
                protoFilterList.name = filterList.name
                protoFilterList.url = filterList.url.absoluteString
                protoFilterList.category = mapFilterListCategory(filterList.category)
                protoFilterList.isSelected = filterList.isSelected
                protoFilterList.description_p = filterList.description
                protoFilterList.version = filterList.version
                if let sourceRuleCount = filterList.sourceRuleCount {
                    protoFilterList.sourceRuleCount = Int32(sourceRuleCount)
                }
                protoFilterList.lastUpdated = Int64(Date().timeIntervalSince1970)
                protoFilterList.isCustom = true

                appendOrMergeMigratedFilterList(protoFilterList, to: &appData)
            }
        }
    }

    private func appendOrMergeMigratedFilterList(
        _ protoFilterList: Wblock_Data_FilterListData,
        to appData: inout Wblock_Data_AppData
    ) {
        if let existingIndex = appData.filterLists.firstIndex(where: { $0.id == protoFilterList.id }) {
            if protoFilterList.isCustom {
                appData.filterLists[existingIndex].isCustom = true
            }
            return
        }

        appData.filterLists.append(protoFilterList)
    }

    private func inferLegacyCustomStatus(for filterList: LegacyFilterList) -> Bool {
        if filterList.isCustom == true || filterList.category == .custom {
            return true
        }

        if isInlineUserListURL(filterList.url) {
            return true
        }

        let normalizedDescription = filterList.description
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedDescription == "user-added filter list."
            || normalizedDescription == "user-added filter list"
            || normalizedDescription == "user list."
            || normalizedDescription == "user list"
    }

    private func isInlineUserListURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "wblock"
            && url.host?.lowercased() == "userlist"
    }
    
    private func migrateUserScripts(from userDefaults: UserDefaults, to appData: inout Wblock_Data_AppData) async {
        if let data = userDefaults.data(forKey: "userScripts"),
           let userScripts = try? JSONDecoder().decode([LegacyUserScript].self, from: data) {
            
            for userScript in userScripts {
                var protoUserScript = Wblock_Data_UserScriptData()
                protoUserScript.id = userScript.id.uuidString
                protoUserScript.name = userScript.name
                protoUserScript.url = userScript.url?.absoluteString ?? ""
                protoUserScript.isEnabled = userScript.isEnabled
                protoUserScript.description_p = userScript.description
                protoUserScript.version = userScript.version
                protoUserScript.matches = userScript.matches
                protoUserScript.excludeMatches = userScript.excludeMatches
                protoUserScript.includes = userScript.includes
                protoUserScript.excludes = userScript.excludes
                protoUserScript.runAt = userScript.runAt
                protoUserScript.injectInto = userScript.injectInto
                protoUserScript.grant = userScript.grant
                protoUserScript.isLocal = userScript.isLocal
                protoUserScript.updateURL = userScript.updateURL ?? ""
                protoUserScript.downloadURL = userScript.downloadURL ?? ""
                protoUserScript.updatesAutomatically = true
                protoUserScript.content = userScript.content
                protoUserScript.lastUpdated = Int64(Date().timeIntervalSince1970)
                
                appData.userScripts.append(protoUserScript)
            }
        }
    }
    
    private func mapFilterListCategory(_ category: LegacyFilterListCategory) -> Wblock_Data_FilterListCategory {
        switch category {
        case .all: return .all
        case .ads: return .ads
        case .privacy: return .privacy
        case .security: return .security
        case .multipurpose: return .multipurpose
        case .annoyances: return .annoyances
        case .experimental: return .experimental
        case .custom: return .custom
        case .foreign: return .foreign
        case .scripts: return .scripts
        case .allowlists: return .allowlists
        }
    }
}

// MARK: - Legacy Data Structures for Migration
private struct LegacyFilterList: Codable {
    let id: UUID
    var name: String
    var url: URL
    var category: LegacyFilterListCategory
    var isSelected: Bool
    var description: String
    var version: String
    var sourceRuleCount: Int?
    var isCustom: Bool?
}

private enum LegacyFilterListCategory: String, Codable, CaseIterable {
    case all = "All"
    case ads = "Ads"
    case privacy = "Privacy"
    case security = "Security"
    case multipurpose = "Multipurpose"
    case annoyances = "Annoyances"
    case experimental = "Experimental"
    case custom = "Custom"
    case foreign = "Foreign"
    case scripts = "Scripts"
    case allowlists = "Allowlists"
}

private struct LegacyUserScript: Codable {
    let id: UUID
    var name: String
    var url: URL?
    var isEnabled: Bool
    var description: String
    var version: String
    var matches: [String]
    var excludeMatches: [String]
    var includes: [String]
    var excludes: [String]
    var runAt: String
    var injectInto: String
    var grant: [String]
    var isLocal: Bool
    var updateURL: String?
    var downloadURL: String?
    var content: String
}

private struct LegacyTabData: Codable {
    var blockedCount: Int
    var isDisabled: Bool
    var host: String
}
