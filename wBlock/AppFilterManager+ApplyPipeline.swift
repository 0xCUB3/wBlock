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

    nonisolated private static func contentBlockerOutputMatchesRules(
        targetRulesFilename: String,
        groupIdentifier: String,
        expectedRulesJSON: String
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

        return fileContents.trimmingCharacters(in: .whitespacesAndNewlines)
            == expectedRulesJSON.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func failApplyRun(
        logMessage: String,
        metadata: [String: String] = [:],
        statusMessage: String? = nil,
        dismissProgressSheet: Bool = false
    ) async {
        await ConcurrentLogManager.shared.error(
            .filterApply,
            logMessage,
            metadata: metadata
        )

        let resolvedStatusMessage = statusMessage
            ?? LocalizedStrings.text("Failed", comment: "Generic failure status")
        await MainActor.run {
            self.hasError = true
            self.statusDescription = resolvedStatusMessage
            self.isLoading = false
            self.applyProgressViewModel.markFailed(message: resolvedStatusMessage)
            if dismissProgressSheet {
                self.showingApplyProgressSheet = false
            }
        }
    }

    // MARK: - Delegated methods

    /// Runs apply-related work exclusively. Concurrent callers are skipped.
    @discardableResult
    func performExclusiveApply(_ work: () async -> Void) async -> Bool {
        if isApplyInFlight {
            await ConcurrentLogManager.shared.warning(
                .filterApply,
                LocalizedStrings.text(
                    "Skipped overlapping apply request",
                    comment: "Apply pipeline concurrency guard"
                ),
                metadata: [:]
            )
            return false
        }

        isApplyInFlight = true
        defer { isApplyInFlight = false }
        await work()
        return true
    }

    func applyChanges(
        allowUserInteraction: Bool = false,
        prepareState: Bool = true,
        skipPreApplyUpdates: Bool = false
    ) async {
        // When prepareState is false, the caller already holds the exclusive apply session
        // (e.g. selected-update download → apply).
        if prepareState {
            let started = await performExclusiveApply {
                await self.applyChangesUnlocked(
                    allowUserInteraction: allowUserInteraction,
                    prepareState: true,
                    skipPreApplyUpdates: skipPreApplyUpdates
                )
            }
            if !started {
                await MainActor.run {
                    // Avoid leaving the UI stuck in a loading state if a second apply was requested.
                    if self.isLoading && !self.showingApplyProgressSheet {
                        self.isLoading = false
                    }
                }
            }
            return
        }

        await applyChangesUnlocked(
            allowUserInteraction: allowUserInteraction,
            prepareState: false,
            skipPreApplyUpdates: skipPreApplyUpdates
        )
    }

    private func applyChangesUnlocked(
        allowUserInteraction: Bool,
        prepareState: Bool,
        skipPreApplyUpdates: Bool
    ) async {
        suppressBlockingOverlay = allowUserInteraction
        defer { suppressBlockingOverlay = false }

        if prepareState {
            await MainActor.run { self.prepareApplyRunState() }
        }

        // While blocking is globally paused, never write real rules back to disk — leave the
        // content blockers empty until the user explicitly resumes. This keeps manual Apply
        // Changes, auto-update runs, and fast disabled-site updates consistent with pause.
        if await MainActor.run(body: { self.isBlockingPaused }) {
            await MainActor.run {
                self.statusDescription = LocalizedStrings.text(
                    "Blocking is paused",
                    comment: "Apply pipeline pause status"
                )
                self.applyProgressViewModel.updateStageDescription(
                    LocalizedStrings.text(
                        "Blocking is paused",
                        comment: "Apply pipeline stage"
                    )
                )
                self.applyProgressViewModel.updatePhaseCompletion(
                    updating: true,
                    scripts: true
                )
            }
            let cleared = await clearAllExtensionsAndEngine()
            await MainActor.run {
                self.lastRuleCount = 0
                self.ruleCountsByExtension.removeAll()
                self.extensionsApproachingLimit.removeAll()
                self.saveRuleCounts()
                self.isLoading = false
                self.showingApplyProgressSheet = false
                if cleared {
                    self.markCurrentStateApplied()
                }
            }
            return
        }

        // Allow the apply progress UI to render fully before heavy work begins.
        let shouldDelayForUI = await MainActor.run { self.showingApplyProgressSheet }
        if shouldDelayForUI {
            await Task.yield()
            await Task.yield()
            try? await Task.sleep(nanoseconds: 280_000_000)  // ~0.28s for sheet presentation + layout
        }

        await ConcurrentLogManager.shared.info(
            .filterApply, LocalizedStrings.text("Starting filter application process"),
            metadata: ["platform": currentPlatform == .macOS ? "macOS" : "iOS"])

        if skipPreApplyUpdates {
            // Selected updates were already downloaded in the review flow. Keep those counts and
            // jump straight into conversion so the user's selection is respected.
            await MainActor.run {
                self.applyProgressViewModel.updatePhaseCompletion(updating: true, scripts: true, reading: false)
                self.statusDescription = LocalizedStrings.text(
                    "Applying filters...\n(This may take a while)",
                    comment: "Apply pipeline filter application status"
                )
                self.applyProgressViewModel.updateStageDescription(
                    LocalizedStrings.text("Applying filters...", comment: "Apply pipeline stage")
                )
            }
        } else {
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
                let refreshResult = await filterUpdater.refreshFiltersIfNeeded(
                    enabledFilters, progressCallback: { prog in
                        Task { @MainActor in
                            self.progress = prog * 0.1
                            self.applyProgressViewModel.updateProgress(Float(prog * 0.1))
                        }
                    }
                )
                let updatedFilters = refreshResult.updated

                await MainActor.run {
                    self.applyProgressViewModel.updateUpdatesFound(updatedFilters.count)
                }

                if refreshResult.failedCount > 0 {
                    await ConcurrentLogManager.shared.warning(
                        .filterApply,
                        LocalizedStrings.text(
                            "Some pre-apply filter updates failed; continuing with available lists",
                            comment: "Apply pipeline soft-fail for pre-apply updates"
                        ),
                        metadata: [
                            "failed": "\(refreshResult.failedCount)",
                            "updated": "\(updatedFilters.count)",
                        ]
                    )
                }

                if !updatedFilters.isEmpty {
                    await saveFilterLists()
                    await ConcurrentLogManager.shared.info(
                        .filterApply, LocalizedStrings.text("Downloaded updates before applying"),
                        metadata: ["count": "\(updatedFilters.count)"])
                } else {
                    await ConcurrentLogManager.shared.info(
                        .filterApply, LocalizedStrings.text("No updates available"), metadata: [:])
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
        }

        let allSelectedFilters = await MainActor.run { self.filterLists.filter { $0.isSelected } }
        let generatedZapperRules = ZapperContentBlockerRuleGenerator.generatedRules(
            from: self.dataManager.getActiveZapperRulesByHost()
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
                .filterApply, LocalizedStrings.text("No filters selected - clearing all extensions"), metadata: [:])

            let cleared = await clearAllExtensionsAndEngine()
            if cleared {
                await MainActor.run {
                    self.isLoading = false
                    self.showingApplyProgressSheet = false
                    self.markCurrentStateApplied()
                    self.lastRuleCount = 0
                    self.ruleCountsByExtension.removeAll()
                    self.extensionsApproachingLimit.removeAll()
                    self.saveRuleCounts()
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

        let disabledSites = self.effectiveFilterDisabledSites()
        let removeParamDNRSummary = await Task.detached(priority: .utility) {
            try? RemoveParamDNRRuleGenerator.saveRules(
                for: allSelectedFilters,
                disabledSites: disabledSites,
                groupIdentifier: GroupIdentifier.shared.value
            )
        }.value
        if let removeParamDNRSummary {
            await ConcurrentLogManager.shared.info(
                .filterApply,
                LocalizedStrings.text("Prepared removeparam DNR rules"),
                metadata: [
                    "generated": "\(removeParamDNRSummary.generatedRules)",
                    "sourceRemoveparam": "\(removeParamDNRSummary.removeParamRules)",
                    "exceptions": "\(removeParamDNRSummary.exceptionRules)",
                    "skipped": "\(removeParamDNRSummary.skippedRules)",
                    "disabledAllow": "\(removeParamDNRSummary.disabledSiteAllowRules)",
                ]
            )
        } else {
            await ConcurrentLogManager.shared.warning(
                .filterApply,
                LocalizedStrings.text("Failed to prepare removeparam DNR rules"),
                metadata: [:]
            )
        }
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

        let conversionWork = platformTargets.map { targetInfo in
            TargetConversionWork(
                targetInfo: targetInfo,
                filters: filtersByTargetInfo[targetInfo] ?? [],
                extraRulesText: targetInfo.slot == 5 ? generatedZapperRulesText : nil
            )
        }
        let groupIdentifier = GroupIdentifier.shared.value
        var conversionCompletions: [ContentBlockerTargetInfo: TargetConversionCompletion] = [:]

        await boundedConcurrentForEach(
            conversionWork,
            operation: { work in
                let conversionStart = Date()
                do {
                    let outcome = try Self.convertOrReuseTargetRules(
                        filters: work.filters,
                        orderedSelectedFilters: orderedSelectedFilters,
                        affinityFilterIDs: affinityFilterIDs,
                        targetInfo: work.targetInfo,
                        allTargets: platformTargets,
                        disabledSites: disabledSites,
                        extraRulesText: work.extraRulesText,
                        groupIdentifier: groupIdentifier
                    )
                    return TargetConversionCompletion(
                        work: work,
                        outcome: outcome,
                        failureDescription: nil,
                        durationMs: Int(Date().timeIntervalSince(conversionStart) * 1000)
                    )
                } catch {
                    return TargetConversionCompletion(
                        work: work,
                        outcome: nil,
                        failureDescription: error.localizedDescription,
                        durationMs: Int(Date().timeIntervalSince(conversionStart) * 1000)
                    )
                }
            },
            onResult: { completion in
                conversionCompletions[completion.work.targetInfo] = completion
                guard let conversionResult = completion.outcome else { return }
                let targetInfo = completion.work.targetInfo
                let blockerName = targetInfo.displayName
                let ruleCountForThisTarget = conversionResult.safariRulesCount

                await MainActor.run {
                    self.applyProgressViewModel.updateStageDescription(
                        LocalizedStrings.format(
                            "Converting %@…",
                            comment: "Apply pipeline converting stage",
                            blockerName
                        )
                    )
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
                        .filterApply, LocalizedStrings.text("Rule limit exceeded for blocker"),
                        metadata: [
                            "blocker": blockerName,
                            "bundleId": targetInfo.bundleIdentifier,
                            "ruleCount": "\(ruleCountForThisTarget)",
                            "ruleLimit": "\(ruleLimit)",
                        ]
                    )
                }
            }
        )

        if let failedTarget = platformTargets.first(where: {
            conversionCompletions[$0]?.failureDescription != nil
        }), let failureDescription = conversionCompletions[failedTarget]?.failureDescription {
            await failApplyRun(
                logMessage: LocalizedStrings.text("Failed to convert rules for blocker"),
                metadata: [
                    "blocker": failedTarget.displayName,
                    "error": failureDescription,
                ]
            )
            return
        }

        for targetInfo in platformTargets {
            guard let completion = conversionCompletions[targetInfo],
                  let conversionResult = completion.outcome else {
                await failApplyRun(
                    logMessage: LocalizedStrings.text("Missing conversion result for blocker"),
                    metadata: ["blocker": targetInfo.displayName]
                )
                return
            }
            let filters = completion.work.filters
            let blockerName = targetInfo.displayName
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
                    durationMs: completion.durationMs
                )
            )


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
            .filterApply, LocalizedStrings.text("Conversion phase summary"),
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
                .filterApply, LocalizedStrings.text("Reload phase summary"),
                metadata: reloadMetadata)
        } else {
            await ConcurrentLogManager.shared.warning(
                .filterApply,
                LocalizedStrings.text("Reload phase had failures; continuing with advanced rules processing"),
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

                let orderedAdvancedRules = platformTargets.compactMap {
                    advancedRulesByTarget[$0.bundleIdentifier]
                }

                try await Task.detached {
                    let combinedAdvancedRules = orderedAdvancedRules.joined(separator: "\n")
                    let totalLines = combinedAdvancedRules.components(separatedBy: "\n").count
                    await ConcurrentLogManager.shared.info(
                        .filterApply, LocalizedStrings.text("Building filter engine"),
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
                    .filterApply, LocalizedStrings.text("No advanced rules found, clearing filter engine"), metadata: [:])
                try await Task.detached {
                    try ContentBlockerService.clearFilterEngine(
                        groupIdentifier: GroupIdentifier.shared.value
                    )
                }.value
            }
            advancedEngineSucceeded = true
        } catch {
            advancedEngineSucceeded = false
            await failApplyRun(
                logMessage: LocalizedStrings.text("Advanced engine publish failed"),
                metadata: ["error": error.localizedDescription],
                dismissProgressSheet: false
            )
        }

        let advancedEngineStatus = advancedRulesByTarget.isEmpty
            ? "cleared"
            : "\(advancedRulesByTarget.count) targets combined"
        await MainActor.run {
            self.progress = 1.0
            self.applyProgressViewModel.updateProgress(1.0)
            self.isLoading = false

            // Hard failure already presented (e.g. advanced engine). Keep that terminal state.
            if self.applyProgressViewModel.state.mode == .failed {
                self.applyProgressViewModel.updateIsLoading(false)
                return
            }

            let advancedEngineAvailable = advancedEngineSucceeded && !self.hasError
            var resultWarning: String?

            if allReloadsSuccessful && advancedEngineAvailable {
                self.statusDescription =
                    "Applied rules to \(filtersByTargetInfo.keys.count) blocker(s). Total: \(overallSafariRulesApplied) Safari rules. Advanced engine: \(advancedEngineStatus)."
                self.markCurrentStateApplied()
            } else if !allReloadsSuccessful {
                // Prefer the concrete reload failure names when available.
                if self.statusDescription.lowercased().contains("failed to reload") {
                    resultWarning = self.statusDescription
                } else {
                    resultWarning = LocalizedStrings.text(
                        "Converted rules, but one or more extensions failed to reload after 5 attempts.",
                        comment: "Apply pipeline partial reload failure warning"
                    )
                    self.statusDescription = resultWarning ?? self.statusDescription
                }
            } else if !advancedEngineAvailable {
                resultWarning = self.statusDescription
            }

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
                statusMessage: self.statusDescription,
                resultWarning: resultWarning
            )
            self.applyProgressViewModel.updateIsLoading(false)
        }
        // Keep showingApplyProgressSheet = true until user dismisses it if it was successful or had errors.
        // Or: showingApplyProgressSheet = false // if you want it to auto-dismiss on error

        await saveFilterLists()

        // Persist rule counts (protobuf store) for next app launch
        saveRuleCounts()

        // Final summary log
        let (hasErrorValueForLog, statusDesc) = await MainActor.run { (self.hasError, self.statusDescription) }

        if allReloadsSuccessful && !hasErrorValueForLog {
            await ConcurrentLogManager.shared.info(
                .filterApply, LocalizedStrings.text("Process completed successfully"), metadata: ["status": statusDesc])
        } else if !hasErrorValueForLog {
            await ConcurrentLogManager.shared.warning(
                .filterApply, LocalizedStrings.text("Process completed with reload issues"),
                metadata: ["status": statusDesc])
        } else {
            await ConcurrentLogManager.shared.error(
                .filterApply, LocalizedStrings.text("Process completed with errors"), metadata: ["status": statusDesc])
        }
    }

    /// Clears the advanced (WebExtension) filter engine, remove-param DNR rules, and writes
    /// an empty `[]` rule list to every content blocker target, then reloads each target.
    /// Used both by the "no filters selected" apply path and by the global pause toggle.
    /// Returns `true` on success, `false` after reporting the failure via `failApplyRun`.
    func clearAllExtensionsAndEngine() async -> Bool {
        let currentPlatform = self.currentPlatform

        do {
            try await Task.detached {
                let groupIdentifier = GroupIdentifier.shared.value
                try ContentBlockerService.clearFilterEngine(
                    groupIdentifier: groupIdentifier
                )
                _ = try RemoveParamDNRRuleGenerator.clearSavedRules(
                    groupIdentifier: groupIdentifier
                )

                let platformTargets = ContentBlockerTargetManager.shared.allTargets(
                    forPlatform: currentPlatform
                )
                var saveFailures: [String] = []
                var targetsToReload: [ContentBlockerTargetInfo] = []

                for targetInfo in platformTargets {
                    let savedRuleCount = try ContentBlockerService.saveContentBlocker(
                        jsonRules: ContentBlockerService.inertContentBlockerRulesJSON,
                        groupIdentifier: groupIdentifier,
                        targetRulesFilename: targetInfo.rulesFilename
                    )
                    let outputMatchesInertRules = Self.contentBlockerOutputMatchesRules(
                        targetRulesFilename: targetInfo.rulesFilename,
                        groupIdentifier: groupIdentifier,
                        expectedRulesJSON: ContentBlockerService.inertContentBlockerRulesJSON
                    )
                    if savedRuleCount == ContentBlockerService.inertContentBlockerRuleCount,
                       outputMatchesInertRules
                    {
                        targetsToReload.append(targetInfo)
                    } else {
                        saveFailures.append(targetInfo.displayName)
                    }
                }

                if !saveFailures.isEmpty {
                    throw ApplyPipelineError.emptyRulesSaveFailed(
                        targetName: saveFailures.joined(separator: ", ")
                    )
                }

                var reloadFailures: [String] = []
                for targetInfo in targetsToReload {
                    let reloadResult = await ContentBlockerService.reloadWithRetry(
                        identifier: targetInfo.bundleIdentifier
                    )
                    if !reloadResult.success {
                        reloadFailures.append(targetInfo.displayName)
                    }
                }

                if !reloadFailures.isEmpty {
                    throw ApplyPipelineError.emptyRulesReloadFailed(
                        targetName: reloadFailures.joined(separator: ", ")
                    )
                }
            }.value
            return true
        } catch {
            await failApplyRun(
                logMessage: LocalizedStrings.text("Failed to clear extensions and advanced engine"),
                metadata: ["error": error.localizedDescription]
            )
            return false
        }
    }

    /// Toggles the global "blocking paused" state.
    ///
    /// When pausing: persists the flag, empties every content blocker (writes `[]`),
    /// clears the advanced WebExtension engine, and reloads Safari. Blocking stays off
    /// across launches and tab switches until the user resumes — see GitHub issue #439.
    ///
    /// When resuming: clears the flag and runs the standard apply pipeline to rebuild
    /// and reload the real rule sets.
    func setBlockingPaused(_ paused: Bool) async {
        if paused {
            let started = await performExclusiveApply {
                BlockingPauseStore.setPaused(true)
                await MainActor.run { self.isBlockingPaused = true }

                await MainActor.run {
                    self.statusDescription = LocalizedStrings.text(
                        "Pausing blocking...",
                        comment: "Apply pipeline pause status"
                    )
                    self.applyProgressViewModel.updateStageDescription(
                        LocalizedStrings.text(
                            "Pausing blocking...",
                            comment: "Apply pipeline stage"
                        )
                    )
                    self.applyProgressViewModel.updatePhaseCompletion(
                        updating: true,
                        scripts: true
                    )
                }
                let cleared = await self.clearAllExtensionsAndEngine()
                await MainActor.run {
                    self.lastRuleCount = 0
                    self.ruleCountsByExtension.removeAll()
                    self.extensionsApproachingLimit.removeAll()
                    self.saveRuleCounts()
                    self.isLoading = false
                    self.showingApplyProgressSheet = false
                    if cleared {
                        self.markCurrentStateApplied()
                        self.statusDescription = LocalizedStrings.text(
                            "Blocking paused",
                            comment: "Apply pipeline pause status"
                        )
                    }
                }
            }
            if !started {
                await ConcurrentLogManager.shared.warning(
                    .filterApply,
                    LocalizedStrings.text(
                        "Skipped pause request while apply is in progress",
                        comment: "Apply pipeline concurrency guard"
                    ),
                    metadata: [:]
                )
            }
        } else {
            BlockingPauseStore.setPaused(false)
            await MainActor.run { self.isBlockingPaused = false }
            await applyChanges()
            await MainActor.run {
                self.statusDescription = LocalizedStrings.text(
                    "Blocking resumed",
                    comment: "Apply pipeline resume status"
                )
            }
        }
    }

    func prepareApplyRunState() {
        isLoading = true
        hasError = false
        progress = 0
        statusDescription = LocalizedStrings.text("Checking for updates...", comment: "Apply pipeline status")

        applyProgressViewModel.beginProgressRun()
        applyProgressViewModel.updateProgress(0)

        sourceRulesCount = 0
        processedFiltersCount = 0
    }

    @MainActor
    public func downloadAndApplyFilters(filters: [FilterList], progress: @escaping (Float) -> Void)
        async
    {
        let started = await performExclusiveApply {
            self.isLoading = true
            self.hasError = false
            self.statusDescription = LocalizedStrings.text(
                "Downloading filter lists...",
                comment: "Apply pipeline status"
            )
            progress(0)

            // Download selected filters using existing updater logic
            let _ = await self.filterUpdater.updateSelectedFilters(
                filters,
                progressCallback: { prog in
                    Task { @MainActor in
                        self.progress = Float(prog)
                        progress(Float(prog))
                    }
                })

            // Save after download
            self.saveFilterListsCoalesced()

            // Apply changes (conversion, reload, etc)
            self.statusDescription = LocalizedStrings.text(
                "Applying filters...\n(This may take a while)",
                comment: "Apply pipeline filter application status"
            )
            await self.applyChangesUnlocked(
                allowUserInteraction: false,
                prepareState: true,
                skipPreApplyUpdates: false
            )

            self.isLoading = false
            progress(1)
            self.statusDescription = LocalizedStrings.text("Ready.", comment: "Filter manager idle status")
        }

        if !started {
            progress(1)
        }
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
                    try ContentBlockerInputWriter.appendFile(
                        from: sourceURL,
                        to: fileHandle,
                        hasher: &hasher,
                        newlineData: newlineData,
                        policy: .strict
                    )
                }
            }

            if let extraRulesText, !extraRulesText.isEmpty {
                try ContentBlockerInputWriter.appendInline(
                    extraRulesText,
                    to: fileHandle,
                    hasher: &hasher,
                    newlineData: newlineData
                )
            }

            let digest = hasher.finalize()
            let rulesSHA256Hex = digest.map { String(format: "%02x", $0) }.joined()

            return try ContentBlockerService.convertFilterFromFile(
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

    private struct TargetConversionOutcome: Sendable {
        let safariRulesCount: Int
        let advancedRulesText: String?
        let reusedCachedBase: Bool
    }

    private struct TargetConversionWork: Sendable {
        let targetInfo: ContentBlockerTargetInfo
        let filters: [FilterList]
        let extraRulesText: String?
    }

    private struct TargetConversionCompletion: Sendable {
        let work: TargetConversionWork
        let outcome: TargetConversionOutcome?
        let failureDescription: String?
        let durationMs: Int
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
        let hasAffinityFilters = filters.contains { affinityFilterIDs.contains($0.id) }
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
            let fastUpdate = try ContentBlockerService.fastUpdateDisabledSites(
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
