import CryptoKit
import SwiftUI
import wBlockCoreService

extension AppFilterManager {
    // MARK: - Helper Methods

    /// Attempts to reload a content blocker with up to 5 retry attempts
    /// Returns true if successful, false if all attempts failed
    func reloadContentBlockerWithRetry(targetInfo: ContentBlockerTargetInfo) async -> Bool {
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

                await saveFilterLists()
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
            self.processedFiltersCount = 0
            self.ruleCountsByExtension = [:]
            self.extensionsApproachingLimit = []

            self.applyProgressViewModel.updatePhaseCompletion(reading: true, converting: false)
            self.applyProgressViewModel.updateConvertingDone(0)
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
                self.progress = Float(self.processedFiltersCount) / Float(totalFiltersCount) * 0.7
                self.applyProgressViewModel.updateProgress(self.progress)
                self.applyProgressViewModel.updateConvertingDone(self.processedFiltersCount)
                self.applyProgressViewModel.updateCurrentFilter(blockerName)
                self.ruleCountsByExtension[targetInfo.bundleIdentifier] = ruleCountForThisTarget

                if ruleCountForThisTarget >= warningThreshold && ruleCountForThisTarget < ruleLimit {
                    self.extensionsApproachingLimit.insert(targetInfo.bundleIdentifier)
                } else {
                    self.extensionsApproachingLimit.remove(targetInfo.bundleIdentifier)
                }

                if ruleCountForThisTarget > ruleLimit {
                    self.hasError = true
                    self.statusDescription =
                        "One or more content blockers exceeded Safari's \(ruleLimit.formatted()) rule limit. Disable some filter lists and try again."
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
            self.applyProgressViewModel.updateProgress(1.0)

            if allReloadsSuccessful && !self.hasError {
                self.statusDescription =
                    "Applied rules to \(filtersByTargetInfo.keys.count) blocker(s). Total: \(overallSafariRulesApplied) Safari rules. Advanced engine: \(advancedRulesByTarget.isEmpty ? "cleared" : "\(advancedRulesByTarget.count) targets combined")."
                self.hasUnappliedChanges = false
            } else if !self.hasError {
                self.statusDescription =
                    "Converted rules, but one or more extensions failed to reload after 5 attempts. Advanced engine: \(advancedRulesByTarget.isEmpty ? "cleared" : "\(advancedRulesByTarget.count) targets combined")."
            }

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

        await saveFilterLists()

        // Save rule counts to UserDefaults for next app launch
        saveRuleCounts()

        // Final summary log
        let (hasErrorValueForLog, statusDesc) = await MainActor.run { (self.hasError, self.statusDescription) }

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

    func prepareApplyRunState() {
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
        saveFilterListsCoalesced()

        // Apply changes (conversion, reload, etc)
        statusDescription = "Applying filters...\n(This may take a while)"
        await applyChanges()

        isLoading = false
        progress(1)
        statusDescription = "Ready."
    }

    // MARK: - Static helpers

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

    struct TargetConversionMetrics {
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

    struct TargetReloadMetrics {
        let blockerName: String
        let success: Bool
        let attempts: Int
        let durationMs: Int
    }

    struct ReloadPhaseSummary {
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

    func reloadContentBlockersInParallel(_ targets: [ContentBlockerTargetInfo], totalCount: Int) async -> ReloadPhaseSummary {
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
