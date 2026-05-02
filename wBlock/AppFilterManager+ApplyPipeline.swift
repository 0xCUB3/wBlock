import CryptoKit
import SwiftUI
import wBlockCoreService

extension AppFilterManager {
    // MARK: - Helper Methods

    private enum ApplyPipelineError: LocalizedError {
        case emptyRulesSaveFailed(targetName: String)
        case emptyRulesReloadFailed(targetName: String)
        case sharedContainerUnavailable
        case conversionFailed(targetName: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case let .emptyRulesSaveFailed(targetName):
                return "Failed to save cleared rules for \(targetName)."
            case let .emptyRulesReloadFailed(targetName):
                return "Failed to reload \(targetName) after clearing rules."
            case .sharedContainerUnavailable:
                return "Shared app group container unavailable."
            case let .conversionFailed(targetName, underlying):
                return "Failed to convert rules for \(targetName): \(underlying.localizedDescription)"
            }
        }
    }

    nonisolated private static func contentBlockerOutputMatchesEmptyArray(
        targetRulesFilename: String,
        groupIdentifier: String
    ) -> Bool {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            return false
        }

        let rulesURL = containerURL.appendingPathComponent(targetRulesFilename)
        guard let fileContents = try? String(contentsOf: rulesURL, encoding: .utf8) else {
            return false
        }

        return fileContents.trimmingCharacters(in: .whitespacesAndNewlines) == "[]"
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
            self.statusDescription = LocalizedStrings.text("Checking for updates...", comment: "Apply pipeline status")
            self.applyProgressViewModel.updateStageDescription(
                LocalizedStrings.text("Checking for updates...", comment: "Apply pipeline stage")
            )
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
                    self.statusDescription = LocalizedStrings.format(
                        "Downloading %d update(s)...",
                        comment: "Apply pipeline update download status",
                        updatedFilters.count
                    )
                    self.applyProgressViewModel.updateStageDescription(
                        LocalizedStrings.format(
                            "Downloading %d update(s)...",
                            comment: "Apply pipeline update download stage",
                            updatedFilters.count
                        )
                    )
                }

                await ConcurrentLogManager.shared.info(
                    .filterApply, "Found and downloading updates before applying",
                    metadata: ["count": "\(updatedFilters.count)"])

                let appliedUpdates = await filterUpdater.updateSelectedFilters(
                    updatedFilters,
                    progressCallback: { prog in
                        Task { @MainActor in
                            self.progress = prog * 0.1  // Use first 10% of progress for updates
                            self.applyProgressViewModel.updateProgress(Float(prog * 0.1))
                        }
                    })
                let requestedIDs = Set(updatedFilters.map(\.id))
                let appliedIDs = Set(appliedUpdates.map(\.id))
                let missingIDs = requestedIDs.subtracting(appliedIDs)
                let unexpectedIDs = appliedIDs.subtracting(requestedIDs)
                guard missingIDs.isEmpty, unexpectedIDs.isEmpty else {
                    await ConcurrentLogManager.shared.error(
                        .filterApply,
                        "Failed to download one or more pre-apply filter updates",
                        metadata: [
                            "requested": "\(updatedFilters.count)",
                            "updated": "\(appliedUpdates.count)",
                            "missingIDs": missingIDs.map(\.uuidString).joined(separator: ","),
                            "unexpectedIDs": unexpectedIDs.map(\.uuidString).joined(separator: ","),
                        ]
                    )
                    await MainActor.run {
                        self.hasError = true
                        self.statusDescription = LocalizedStrings.text(
                            "Failed",
                            comment: "Generic failure status"
                        )
                        self.isLoading = false
                        self.showingApplyProgressSheet = false
                    }
                    return
                }

                await saveFilterLists()
            } else {
                await ConcurrentLogManager.shared.info(
                    .filterApply, "No updates available", metadata: [:])
            }
        }

        // Mark updating phase as complete
        await MainActor.run {
            self.applyProgressViewModel.updatePhaseCompletion(updating: true, scripts: false)
            self.statusDescription = LocalizedStrings.text(
                "Applying filters...\n(This may take a while)",
                comment: "Apply pipeline filter application status"
            )
            self.applyProgressViewModel.updateStageDescription(
                LocalizedStrings.text("Applying filters...", comment: "Apply pipeline stage")
            )
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
        let generatedZapperRules = ZapperContentBlockerRuleGenerator.generatedRules(
            from: Dictionary(
                uniqueKeysWithValues: self.dataManager.getZapperDomains().map { host in
                    (host, self.dataManager.getZapperRules(forHost: host))
                }
            )
        )
        let generatedZapperRulesText = generatedZapperRules.isEmpty
            ? nil
            : generatedZapperRules.joined(separator: "\n")

        if allSelectedFilters.isEmpty && generatedZapperRules.isEmpty {
            await MainActor.run {
                self.statusDescription = LocalizedStrings.text(
                    "No filter lists selected. Clearing rules from all extensions.",
                    comment: "Apply pipeline no filters status"
                )
            }
            await ConcurrentLogManager.shared.info(
                .filterApply, "No filters selected - clearing all extensions", metadata: [:])

            let currentPlatform = self.currentPlatform

            do {
                try await Task.detached {
                    let groupIdentifier = GroupIdentifier.shared.value
                    try ContentBlockerService.clearFilterEngine(
                        groupIdentifier: groupIdentifier
                    )

                    let platformTargets = ContentBlockerTargetManager.shared.allTargets(
                        forPlatform: currentPlatform
                    )
                    for targetInfo in platformTargets {
                        let savedRuleCount = ContentBlockerService.saveContentBlocker(
                            jsonRules: "[]",
                            groupIdentifier: groupIdentifier,
                            targetRulesFilename: targetInfo.rulesFilename
                        )
                        let outputMatchesEmptyArray = Self.contentBlockerOutputMatchesEmptyArray(
                            targetRulesFilename: targetInfo.rulesFilename,
                            groupIdentifier: groupIdentifier
                        )
                        guard savedRuleCount == 0, outputMatchesEmptyArray else {
                            throw ApplyPipelineError.emptyRulesSaveFailed(
                                targetName: targetInfo.displayName
                            )
                        }

                        let reloadResult = await ContentBlockerService.reloadWithRetry(
                            identifier: targetInfo.bundleIdentifier
                        )
                        guard reloadResult.success else {
                            throw ApplyPipelineError.emptyRulesReloadFailed(
                                targetName: targetInfo.displayName
                            )
                        }
                    }
                }.value

                await MainActor.run {
                    self.isLoading = false
                    self.showingApplyProgressSheet = false
                    self.markCurrentStateApplied()
                    self.lastRuleCount = 0
                    self.ruleCountsByExtension.removeAll()
                    self.extensionsApproachingLimit.removeAll()
                    self.saveRuleCounts()
                }
            } catch {
                await ConcurrentLogManager.shared.error(
                    .filterApply,
                    "Failed to clear extensions and advanced engine",
                    metadata: ["error": error.localizedDescription]
                )
                await MainActor.run {
                    self.hasError = true
                    self.statusDescription = LocalizedStrings.text(
                        "Failed",
                        comment: "Generic failure status"
                    )
                    self.isLoading = false
                    self.showingApplyProgressSheet = false
                }
            }
            return
        }

        let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: self.currentPlatform)
        let orderedSelectedFilters = ContentBlockerMappingService.orderedForDistribution(allSelectedFilters)

        let filtersByTargetInfo = ContentBlockerMappingService.distribute(
            selectedFilters: allSelectedFilters,
            across: platformTargets
        )

        let totalFiltersCount = platformTargets.count
        await MainActor.run {
            self.sourceRulesCount = allSelectedFilters.reduce(0) { $0 + ($1.sourceRuleCount ?? 0) }
                + generatedZapperRules.count

            // Update ViewModel
            self.applyProgressViewModel.updateProcessedCount(0, total: totalFiltersCount)
            self.applyProgressViewModel.updateConvertingDone(0)
            self.applyProgressViewModel.updateReloadingDone(0)
            self.applyProgressViewModel.updateStageDescription(
                LocalizedStrings.text("Starting conversion...", comment: "Apply pipeline stage")
            )
        }

        if totalFiltersCount == 0 {
            await MainActor.run {
                self.statusDescription = LocalizedStrings.text(
                    "No matching extensions for selected filters.",
                    comment: "Apply pipeline no matching extensions status"
                )
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
        let affinityFilterIDs: Set<UUID> = await Task.detached(priority: .utility) {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value
            ) else {
                return []
            }

            return SafariContentBlockerAffinityProcessor.detectFiltersWithAffinity(
                orderedSelectedFilters,
                containerURL: containerURL
            )
        }.value

        for targetInfo in platformTargets {
            let filters = filtersByTargetInfo[targetInfo] ?? []
            let extraRulesText = targetInfo.slot == 5 ? generatedZapperRulesText : nil
            let blockerName = targetInfo.displayName
            let conversionStart = Date()

            await MainActor.run {
                self.applyProgressViewModel.updateStageDescription(
                    LocalizedStrings.format(
                        "Converting %@…",
                        comment: "Apply pipeline converting stage",
                        blockerName
                    )
                )
            }

            // Yield to prevent main thread starvation on iOS
            await Task.yield()

            let conversionResult: TargetConversionOutcome
            do {
                conversionResult = try await Task.detached {
                    try Self.convertOrReuseTargetRules(
                        filters: filters,
                        orderedSelectedFilters: orderedSelectedFilters,
                        affinityFilterIDs: affinityFilterIDs,
                        targetInfo: targetInfo,
                        allTargets: platformTargets,
                        disabledSites: disabledSites,
                        extraRulesText: extraRulesText,
                        groupIdentifier: GroupIdentifier.shared.value
                    )
                }.value
            } catch {
                await ConcurrentLogManager.shared.error(
                    .filterApply,
                    "Failed to convert rules for blocker",
                    metadata: ["blocker": blockerName, "error": error.localizedDescription]
                )
                await MainActor.run {
                    self.hasError = true
                    self.statusDescription = LocalizedStrings.text(
                        "Failed",
                        comment: "Generic failure status"
                    )
                    self.isLoading = false
                    self.showingApplyProgressSheet = false
                }
                return
            }
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
            self.applyProgressViewModel.updateStageDescription(
                LocalizedStrings.text("Reloading Safari extensions...", comment: "Apply pipeline stage")
            )
            self.applyProgressViewModel.updateProcessedCount(0, total: totalFiltersCount)
            self.applyProgressViewModel.updateReloadingDone(0)
            self.applyProgressViewModel.updateCurrentFilter("")
        }

        let overallReloadStartTime = Date()
        let reloadSummary = await reloadContentBlockers(platformTargets)
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

        let advancedEngineSucceeded: Bool
        do {
            if !advancedRulesByTarget.isEmpty {
                await MainActor.run {
                    self.applyProgressViewModel.updateStageDescription(
                        LocalizedStrings.text("Building combined filter engine...", comment: "Apply pipeline stage")
                    )
                }

                try await Task.detached {
                    let combinedAdvancedRules = advancedRulesByTarget.values.joined(separator: "\n")
                    let totalLines = combinedAdvancedRules.components(separatedBy: "\n").count
                    await ConcurrentLogManager.shared.info(
                        .filterApply, "Building filter engine",
                        metadata: [
                            "targetCount": "\(advancedRulesByTarget.count)",
                            "totalLines": "\(totalLines)",
                        ])

                    try ContentBlockerService.buildCombinedFilterEngine(
                        combinedAdvancedRules: combinedAdvancedRules,
                        groupIdentifier: GroupIdentifier.shared.value
                    )
                }.value
            } else {
                await ConcurrentLogManager.shared.debug(
                    .filterApply, "No advanced rules found, clearing filter engine", metadata: [:])
                try await Task.detached {
                    try ContentBlockerService.clearFilterEngine(
                        groupIdentifier: GroupIdentifier.shared.value
                    )
                }.value
            }
            advancedEngineSucceeded = true
        } catch {
            advancedEngineSucceeded = false
            await ConcurrentLogManager.shared.error(
                .filterApply,
                "Advanced engine publish failed",
                metadata: ["error": error.localizedDescription]
            )
            await MainActor.run {
                self.hasError = true
                self.statusDescription = LocalizedStrings.text(
                    "Failed",
                    comment: "Generic failure status"
                )
            }
        }

        await MainActor.run {
            self.progress = 1.0
            self.applyProgressViewModel.updateProgress(1.0)

            let advancedEngineAvailable = advancedEngineSucceeded && !self.hasError
            if allReloadsSuccessful && advancedEngineAvailable {
                self.statusDescription =
                    "Applied rules to \(filtersByTargetInfo.keys.count) blocker(s). Total: \(overallSafariRulesApplied) Safari rules. Advanced engine: \(advancedRulesByTarget.isEmpty ? "cleared" : "\(advancedRulesByTarget.count) targets combined")."
                self.markCurrentStateApplied()
            } else if advancedEngineAvailable {
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
        statusDescription = LocalizedStrings.text("Checking for updates...", comment: "Apply pipeline status")

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
        statusDescription = LocalizedStrings.text("Downloading filter lists...", comment: "Apply pipeline status")
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
        statusDescription = LocalizedStrings.text(
            "Applying filters...\n(This may take a while)",
            comment: "Apply pipeline filter application status"
        )
        await applyChanges()

        isLoading = false
        progress(1)
        statusDescription = LocalizedStrings.text("Ready.", comment: "Filter manager idle status")
    }

    // MARK: - Static helpers

    /// Memory-efficient conversion that combines filter files using streaming I/O
    nonisolated private static func convertFiltersMemoryEfficient(
        filters: [FilterList],
        orderedSelectedFilters: [FilterList],
        affinityFilterIDs: Set<UUID>,
        targetInfo: ContentBlockerTargetInfo,
        allTargets: [ContentBlockerTargetInfo],
        disabledSites: [String],
        extraRulesText: String?,
        groupIdentifier: String
    ) throws -> (safariRulesCount: Int, advancedRulesText: String?) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else {
            throw ApplyPipelineError.sharedContainerUnavailable
        }

        let tempURL = containerURL.appendingPathComponent("temp_\(targetInfo.bundleIdentifier).txt")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        do {
            FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
            let fileHandle = try FileHandle(forWritingTo: tempURL)
            defer { try? fileHandle.close() }

            var hasher = SHA256()
            let newlineData = Data("\n".utf8)
            let assignedFilterIDs = Set(filters.map(\.id))

            for filter in orderedSelectedFilters {
                let includeBaseRules = assignedFilterIDs.contains(filter.id)
                let hasAffinity = affinityFilterIDs.contains(filter.id)
                guard includeBaseRules || hasAffinity else { continue }

                if hasAffinity {
                    try SafariContentBlockerAffinityProcessor.appendAffinityFilteredContribution(
                        for: filter,
                        includeBaseRules: includeBaseRules,
                        target: targetInfo,
                        allTargets: allTargets,
                        containerURL: containerURL,
                        destinationHandle: fileHandle,
                        hasher: &hasher,
                        newlineData: newlineData
                    )
                } else if let sourceURL = SafariContentBlockerAffinityProcessor.sourceURL(
                    for: filter,
                    containerURL: containerURL
                ) {
                    try Self.appendFileContentsToCombinedStream(
                        sourceURL: sourceURL,
                        destinationHandle: fileHandle,
                        hasher: &hasher,
                        newlineData: newlineData
                    )
                }
            }

            if let extraRulesText, !extraRulesText.isEmpty {
                try Self.appendInlineRulesToCombinedStream(
                    extraRulesText,
                    destinationHandle: fileHandle,
                    hasher: &hasher,
                    newlineData: newlineData
                )
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
            throw ApplyPipelineError.conversionFailed(
                targetName: targetInfo.displayName,
                underlying: error
            )
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
        orderedSelectedFilters: [FilterList],
        affinityFilterIDs: Set<UUID>,
        targetInfo: ContentBlockerTargetInfo,
        allTargets: [ContentBlockerTargetInfo],
        disabledSites: [String],
        extraRulesText: String?,
        groupIdentifier: String
    ) throws -> TargetConversionOutcome {
        let rulesFilename = targetInfo.rulesFilename
        let hasAffinityFilters = !affinityFilterIDs.isEmpty
        let currentSignature = hasAffinityFilters
            ? nil
            : ContentBlockerIncrementalCache.computeInputSignature(
                filters: filters,
                groupIdentifier: groupIdentifier,
                extraRulesText: extraRulesText
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
           ) {
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

        if hasAffinityFilters {
            ContentBlockerIncrementalCache.invalidateInputSignature(
                targetRulesFilename: rulesFilename,
                groupIdentifier: groupIdentifier
            )
        }

        let conversion = try convertFiltersMemoryEfficient(
            filters: filters,
            orderedSelectedFilters: orderedSelectedFilters,
            affinityFilterIDs: affinityFilterIDs,
            targetInfo: targetInfo,
            allTargets: allTargets,
            disabledSites: disabledSites,
            extraRulesText: extraRulesText,
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

    nonisolated private static func appendInlineRulesToCombinedStream(
        _ rulesText: String,
        destinationHandle: FileHandle,
        hasher: inout SHA256,
        newlineData: Data
    ) throws {
        let rulesData = Data(rulesText.utf8)
        hasher.update(data: rulesData)
        try destinationHandle.write(contentsOf: rulesData)
        hasher.update(data: newlineData)
        try destinationHandle.write(contentsOf: newlineData)
    }

    func reloadContentBlockers(_ targets: [ContentBlockerTargetInfo]) async -> ReloadPhaseSummary {
        let totalCount = targets.count
        var allSuccessful = true
        var metrics: [TargetReloadMetrics] = []
        var failedNames: [String] = []

        for target in targets {
            let name = target.displayName

            await MainActor.run {
                self.processedFiltersCount += 1
                self.applyProgressViewModel.updateCurrentFilter(name)
                self.applyProgressViewModel.updateReloadingDone(self.processedFiltersCount)

                self.progress =
                    0.7 + (Float(self.processedFiltersCount) / Float(max(1, totalCount)) * 0.2)
                self.applyProgressViewModel.updateProgress(self.progress)
            }

            let reloadResult = await ContentBlockerService.reloadWithRetry(
                identifier: target.bundleIdentifier
            )

            if !reloadResult.success {
                failedNames.append(name)
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
        }

        await MainActor.run {
            guard !failedNames.isEmpty else { return }
            if !self.hasError {
                self.statusDescription = LocalizedStrings.format(
                    "Failed to reload %@.",
                    comment: "Apply pipeline reload failure status",
                    failedNames.joined(separator: ", ")
                )
            }
            self.hasError = true
        }

        return ReloadPhaseSummary(allSuccessful: allSuccessful, metrics: metrics)
    }

}
