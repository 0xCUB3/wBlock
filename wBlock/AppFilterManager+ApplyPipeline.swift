import CryptoKit
import SwiftUI
import wBlockCoreService

extension AppFilterManager {
    // MARK: - Helper Methods

    private enum ApplyPipelineError: LocalizedError {
        case emptyRulesSaveFailed(targetName: String)
        case emptyRulesReloadFailed(targetName: String)

        var errorDescription: String? {
            switch self {
            case let .emptyRulesSaveFailed(targetName):
                return "Failed to save cleared rules for \(targetName)."
            case let .emptyRulesReloadFailed(targetName):
                return "Failed to reload \(targetName) after clearing rules."
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
                    let outcome = try ContentBlockerService.compileTargetRules(
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
                
                let blockerName = completion.work.targetInfo.displayName
                let ruleCountForThisTarget = conversionResult.safariRulesCount
                
                // Batch UI updates to reduce Main Actor calls
                self.processedFiltersCount += 1
                if self.processedFiltersCount % max(1, totalFiltersCount / 5) == 0 || self.processedFiltersCount == totalFiltersCount {
                    Task { @MainActor in
                        self.applyProgressViewModel.updateStageDescription(
                            LocalizedStrings.format("Converting %@…", comment: "Apply pipeline converting stage", blockerName)
                        )
                        self.progress = Float(self.processedFiltersCount) / Float(totalFiltersCount) * 0.7
                        self.applyProgressViewModel.updateProgress(self.progress)
                        self.applyProgressViewModel.updateConvertingDone(self.processedFiltersCount)
                        self.applyProgressViewModel.updateCurrentFilter(blockerName)
                        
                        if ruleCountForThisTarget > ruleLimit {
                            self.hasError = true
                            self.statusDescription = "One or more content blockers exceeded Safari's \(ruleLimit.formatted()) rule limit. Disable some filter lists and try again."
                        } else if ruleCountForThisTarget >= warningThreshold {
                            self.extensionsApproachingLimit.insert(completion.work.targetInfo.bundleIdentifier)
                        }
                    }
                }
                
                self.ruleCountsByExtension[completion.work.targetInfo.bundleIdentifier] = ruleCountForThisTarget

                if ruleCountForThisTarget > ruleLimit {
                    await ConcurrentLogManager.shared.error(
                        .filterApply, LocalizedStrings.text("Rule limit exceeded for blocker"),
                        metadata: [
                            "blocker": blockerName,
                            "bundleId": completion.work.targetInfo.bundleIdentifier,
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
        
        // Aggregate conversion metrics (reduces Main Actor round-trips)
        var totalRules = 0
        let aggregatedMetrics = platformTargets.compactMap { targetInfo -> TargetConversionMetrics? in
            guard let completion = conversionCompletions[targetInfo],
                  let conversionResult = completion.outcome else {
                return nil
            }
            
            let blockerName = targetInfo.displayName
            let ruleCountForThisTarget = conversionResult.safariRulesCount
            totalRules += ruleCountForThisTarget
            
            if let advancedRulesText = conversionResult.advancedRulesText, !advancedRulesText.isEmpty {
                advancedRulesByTarget[targetInfo.bundleIdentifier] = advancedRulesText
            } else {
                advancedRulesByTarget.removeValue(forKey: targetInfo.bundleIdentifier)
            }
            
            return TargetConversionMetrics(
                blockerName: blockerName,
                filterCount: completion.work.filters.count,
                safariRules: ruleCountForThisTarget,
                advancedRules: conversionResult.advancedRulesText?.components(separatedBy: .newlines).count ?? 0,
                reusedCachedBase: conversionResult.reusedCachedBase,
                durationMs: completion.durationMs
            )
        }
        
        conversionMetrics = aggregatedMetrics
        
        await MainActor.run {
            self.lastRuleCount = totalRules
            self.lastConversionTime = String(format: "%.2fs", Date().timeIntervalSince(overallConversionStartTime))
            self.progress = 0.7
            self.applyProgressViewModel.updatePhaseCompletion(converting: true, saving: false)
        }
        
        let cacheHits = conversionMetrics.filter { $0.reusedCachedBase }.count
        
        // Log conversion summary and start reload phase in one batch
        let cacheMisses = conversionMetrics.count - cacheHits
        let totalRulesMetric = conversionMetrics.reduce(0) { $0 + $1.safariRules }
        let totalFiltersMetric = conversionMetrics.reduce(0) { $0 + $1.filterCount }
        let avgTargetMs = conversionMetrics.isEmpty ? 0 : conversionMetrics.reduce(0) { $0 + $1.durationMs } / conversionMetrics.count
        let slowestTarget = conversionMetrics.max(by: { $0.durationMs < $1.durationMs })?.blockerName
        
        await ConcurrentLogManager.shared.info(
            .filterApply, LocalizedStrings.text("Conversion phase summary"),
            metadata: [
                "targets": "\(conversionMetrics.count)",
                "assignedFilters": "\(totalFiltersMetric)",
                "cacheHits": "\(cacheHits)",
                "cacheMisses": "\(cacheMisses)",
                "totalRules": "\(totalRulesMetric)",
                "advancedRules": "\(conversionMetrics.reduce(0) { $0 + $1.advancedRules })",
                "avgTargetMs": "\(avgTargetMs)",
                "slowestTarget": slowestTarget ?? "n/a",
            ])
        
        await MainActor.run {
            self.processedFiltersCount = 0
            self.applyProgressViewModel.updatePhaseCompletion(saving: true, reloading: false)
            self.applyProgressViewModel.updateStageDescription(
                LocalizedStrings.text("Reloading Safari extensions...", comment: "Apply pipeline stage")
            )
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
        
        // Compact reload logging
        let reloadMetadata: [String: String] = [
            "targets": "\(reloadSummary.metrics.count)",
            "failedTargets": "\(failedReloads.count)",
            "retriedTargets": "\(retriedReloads.count)",
            "totalAttempts": "\(reloadSummary.metrics.reduce(0) { $0 + $1.attempts })",
            "avgAttempts": String(format: "%.2f", (Double(reloadSummary.metrics.count) > 0) ? Double(reloadSummary.metrics.reduce(0) { $0 + $1.attempts }) / Double(reloadSummary.metrics.count) : 0),
            "slowestTarget": reloadSummary.metrics.max(by: { $0.durationMs < $1.durationMs })?.blockerName ?? "n/a",
        ]

        await ConcurrentLogManager.shared.info(
            .filterApply,
            allReloadsSuccessful ? LocalizedStrings.text("Reload phase summary") : LocalizedStrings.text("Reload phase had failures; continuing with advanced rules processing"),
            metadata: reloadMetadata)

        // Batch final UI updates with reload time calculation
        await MainActor.run {
            self.lastReloadTime = String(format: "%.2fs", Date().timeIntervalSince(overallReloadStartTime))
            self.progress = 0.9
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

                try await Task.detached { [weak self] in
                    let combinedAdvancedRules = orderedAdvancedRules.joined(separator: "\n")
                    await ConcurrentLogManager.shared.info(
                        .filterApply,
                        !combinedAdvancedRules.isEmpty ? LocalizedStrings.text("Building filter engine") : LocalizedStrings.text("No advanced rules, clearing filter engine"),
                        metadata: ["targetCount": "\(advancedRulesByTarget.count)"]
                    )
                    
                    if combinedAdvancedRules.isEmpty {
                        try ContentBlockerService.clearFilterEngine(groupIdentifier: GroupIdentifier.shared.value)
                    } else {
                        try ContentBlockerService.buildCombinedFilterEngine(combinedAdvancedRules: combinedAdvancedRules, groupIdentifier: GroupIdentifier.shared.value)
                    }
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

        let advancedEngineStatus = advancedRulesByTarget.isEmpty ? "cleared" : "\(advancedRulesByTarget.count) targets combined"
        
        // Compact final UI batch
        await MainActor.run {
            self.progress = 1.0
            self.applyProgressViewModel.updateProgress(1.0)
            self.isLoading = false
            
            guard self.applyProgressViewModel.state.mode != .failed else {
                self.applyProgressViewModel.updateIsLoading(false)
                return
            }
            
            var resultWarning: String?
            if allReloadsSuccessful {
                self.statusDescription = "Applied rules to \(filtersByTargetInfo.keys.count) blocker(s). Total: \(overallSafariRulesApplied) Safari rules. Advanced engine: \(advancedEngineStatus)."
                self.markCurrentStateApplied()
            } else {
                resultWarning = LocalizedStrings.text("Converted rules, but one or more extensions failed to reload after 5 attempts.", comment: "Apply pipeline partial reload failure warning")
                self.hasError = true
            }
            
            let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: self.currentPlatform)
            self.applyProgressViewModel.updateStatistics(
                sourceRules: self.sourceRulesCount,
                safariRules: self.lastRuleCount,
                conversionTime: self.lastConversionTime,
                reloadTime: self.lastReloadTime,
                ruleCountsByBlocker: Dictionary(uniqueKeysWithValues: platformTargets.map { (target: ContentBlockerTargetInfo) -> (String, Int) in
                    (target.displayName, self.ruleCountsByExtension[target.bundleIdentifier] ?? 0)
                }),
                blockersApproachingLimit: Set(platformTargets.filter { self.extensionsApproachingLimit.contains($0.bundleIdentifier) }.map { $0.displayName }),
                statusMessage: self.statusDescription,
                resultWarning: resultWarning
            )
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
            try await Task.detached { [weak self] in
                guard let self else { return }
                let groupIdentifier = GroupIdentifier.shared.value
                
                // Clear advanced engine in background
                try ContentBlockerService.clearFilterEngine(groupIdentifier: groupIdentifier)
                _ = try RemoveParamDNRRuleGenerator.clearSavedRules(groupIdentifier: groupIdentifier)
                
                let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
                
                // Parallel save of inert rules to all targets
                let saveTasks = platformTargets.map { targetInfo in
                    Task.detached(priority: .utility) {
                        let savedRuleCount = try ContentBlockerService.saveContentBlocker(
                            jsonRules: ContentBlockerService.inertContentBlockerRulesJSON,
                            groupIdentifier: groupIdentifier,
                            targetRulesFilename: targetInfo.rulesFilename
                        )
                        let matches = Self.contentBlockerOutputMatchesRules(
                            targetRulesFilename: targetInfo.rulesFilename,
                            groupIdentifier: groupIdentifier,
                            expectedRulesJSON: ContentBlockerService.inertContentBlockerRulesJSON
                        )
                        return (targetInfo, savedRuleCount == ContentBlockerService.inertContentBlockerRuleCount && matches)
                    }
                }
                
                var targetsToReload: [ContentBlockerTargetInfo] = []
                for try await result in saveTasks {
                    if result.1 { targetsToReload.append(result.0) }
                }
                
                guard !targetsToReload.isEmpty else {
                    throw ApplyPipelineError.emptyRulesSaveFailed(
                        targetName: platformTargets.map { $0.displayName }.joined(separator: ", ")
                    )
                }
                
                // Parallel reload of all targets
                let reloadTasks = targetsToReload.map { target in
                    Task.detached(priority: .utility) {
                        await ContentBlockerService.reloadWithRetry(identifier: target.bundleIdentifier)
                    }
                }
                
                var reloadFailures: [String] = []
                for try await result in reloadTasks {
                    if !result.success {
                        reloadFailures.append(result.blockerName)
                    }
                }
                
                guard reloadFailures.isEmpty else {
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
                UserScriptManager.invalidateDocumentStartExecutionCache()
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
            UserScriptManager.invalidateDocumentStartExecutionCache()
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
    private struct TargetConversionWork: Sendable {
        let targetInfo: ContentBlockerTargetInfo
        let filters: [FilterList]
        let extraRulesText: String?
    }

    private struct TargetConversionCompletion: Sendable {
        let work: TargetConversionWork
        let outcome: ContentBlockerService.ContentBlockerTargetOutcome?
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




    func reloadContentBlockers(_ targets: [ContentBlockerTargetInfo]) async -> ReloadPhaseSummary {
        let totalCount = targets.count
        
        // Parallel reload all content blockers simultaneously (faster than sequential)
        let reloadTasks = targets.map { target in
            Task.detached(priority: .utility) {
                let startTime = Date()
                let result = await ContentBlockerService.reloadWithRetry(
                    identifier: target.bundleIdentifier
                )
                return TargetReloadMetrics(
                    blockerName: target.displayName,
                    success: result.success,
                    attempts: result.attempts,
                    durationMs: Int(Date().timeIntervalSince(startTime) * 1000)
                )
            }
        }
        
        let metrics = await withTaskGroup(of: TargetReloadMetrics.self) { group in
            for task in reloadTasks {
                group.addTask { await task.value }
            }
            var results: [TargetReloadMetrics] = []
            for try await metric in group {
                results.append(metric)
            }
            return results
        }
        
        let failedNames = metrics.filter { !$0.success }.map { $0.blockerName }
        let allSuccessful = failedNames.isEmpty
        
        await MainActor.run {
            self.processedFiltersCount = totalCount
            self.applyProgressViewModel.updateReloadingDone(totalCount)
            self.progress = 0.9
            self.applyProgressViewModel.updateProgress(0.9)
            
            if !failedNames.isEmpty, !self.hasError {
                self.statusDescription = LocalizedStrings.format(
                    "Failed to reload %@.",
                    comment: "Apply pipeline reload failure status",
                    failedNames.joined(separator: ", ")
                )
                self.hasError = true
            }
        }
        
        return ReloadPhaseSummary(allSuccessful: allSuccessful, metrics: metrics)
    }

}
