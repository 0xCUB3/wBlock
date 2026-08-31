import CryptoKit
import SwiftUI
import wBlockCoreService
#if os(iOS)
import UIKit
#endif

#if os(iOS)
/// Cooperative cancel flag for the in-flight apply. Expiration callbacks set
/// this off the MainActor so checkpoints can unwind and drop app-group file
/// locks before iOS suspends (0xDEAD10CC).
private enum ApplyCancellation {
    private static let lock = NSLock()
    private static var cancelled = false

    static func reset() {
        lock.lock()
        cancelled = false
        lock.unlock()
    }

    static func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    static var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// Holds `performExpiringActivity` while apply owns shared-container locks.
/// The non-expired callback blocks on a background thread; `release()` wakes
/// every callback waiting for the apply to unwind. When expiration starts, the
/// callback waits briefly for the locks to drop before allowing suspension so
/// iOS does not kill the process with 0xDEAD10CC.
private final class ApplySuspensionShield: @unchecked Sendable {
    private static let expirationUnwindTimeout: TimeInterval = 3

    private let condition = NSCondition()
    private var expired = false
    private var released = false

    init(reason: String, onExpiration: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { [weak self] isExpired in
                if isExpired {
                    self?.markExpired()
                    onExpiration()
                    self?.waitUntilReleased(
                        timeout: ApplySuspensionShield.expirationUnwindTimeout
                    )
                } else {
                    self?.waitUntilReleased()
                }
            }
        }
    }

    var isExpired: Bool {
        condition.lock()
        defer { condition.unlock() }
        return expired
    }

    private func markExpired() {
        condition.lock()
        expired = true
        condition.unlock()
    }

    private func waitUntilReleased(timeout: TimeInterval? = nil) {
        condition.lock()
        defer { condition.unlock() }

        if let timeout {
            let deadline = Date().addingTimeInterval(timeout)
            while !released && condition.wait(until: deadline) {}
        } else {
            while !released {
                condition.wait()
            }
        }
    }

    func release() {
        condition.lock()
        guard !released else {
            condition.unlock()
            return
        }
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

@MainActor
private final class ApplyBackgroundTaskHandle {
    private let application: UIApplication
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(application: UIApplication) {
        self.application = application
    }

    @discardableResult
    func start(name: String, onExpiration: @escaping @Sendable () -> Void) -> Bool {
        identifier = application.beginBackgroundTask(withName: name) { [weak self] in
            onExpiration()
            Task { @MainActor in
                self?.end()
            }
        }
        return identifier != .invalid
    }

    func end() {
        guard identifier != .invalid else { return }
        application.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif

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
            self.autoApplyTask?.cancel()
            self.autoApplyTask = nil
            self.persistFailedUpgradeRebuildSignature()
            self.lastApplySucceeded = false
            self.hasError = true
            self.statusDescription = resolvedStatusMessage
            self.isLoading = false
            self.applyProgressViewModel.markFailed(message: resolvedStatusMessage)
            if dismissProgressSheet {
                self.showingApplyProgressSheet = false
            }
        }
    }

    /// Fails the in-flight apply when iOS is about to suspend so file locks
    /// unwind instead of killing the process with 0xDEAD10CC.
    private func failApplyIfCancelled() async -> Bool {
        #if os(iOS)
        guard ApplyCancellation.isCancelled || Task.isCancelled else {
            return false
        }
        await failApplyRun(
            logMessage: LocalizedStrings.text(
                "Apply cancelled to release file locks before suspension",
                comment: "Apply pipeline suspension cancel"
            )
        )
        return true
        #else
        return false
        #endif
    }

    // MARK: - Delegated methods

    /// Runs apply-related work exclusively. Concurrent callers are skipped.
    /// On iOS the session also holds a suspension shield so closing the app
    /// mid-apply can unwind shared-container locks instead of dying (0xDEAD10CC).
    @discardableResult
    func performExclusiveApply(_ work: @escaping () async -> Void) async -> Bool {
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
        defer {
            isApplyInFlight = false
            if lastApplySucceeded
                && hasUnappliedChanges
                && !BlockingPauseStore.isPaused(.filters) {
                scheduleAutoApplyDebounce()
            }
        }

        #if os(iOS)
        ApplyCancellation.reset()
        let applyTask = Task {
            await work()
        }
        let shield = ApplySuspensionShield(reason: "wBlock apply") {
            ApplyCancellation.cancel()
            applyTask.cancel()
        }
        let backgroundTask = ApplyBackgroundTaskHandle(application: .shared)
        backgroundTask.start(name: "wBlock apply") {
            ApplyCancellation.cancel()
            applyTask.cancel()
        }
        defer { shield.release() }
        defer { backgroundTask.end() }
        await applyTask.value
        #else
        await work()
        #endif
        return true
    }

    func applyChanges(
        allowUserInteraction: Bool = false,
        prepareState: Bool = true,
        skipPreApplyUpdates: Bool = false,
        allowPausedResume: Bool = false
    ) async {
        // When prepareState is false, the caller already holds the exclusive apply session
        // (e.g. selected-update download → apply).
        if prepareState {
            let started = await performExclusiveApply {
                await self.applyChangesUnlocked(
                    allowUserInteraction: allowUserInteraction,
                    prepareState: true,
                    skipPreApplyUpdates: skipPreApplyUpdates,
                    allowPausedResume: allowPausedResume
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
            skipPreApplyUpdates: skipPreApplyUpdates,
            allowPausedResume: allowPausedResume
        )
    }

    private func applyChangesUnlocked(
        allowUserInteraction: Bool,
        prepareState: Bool,
        skipPreApplyUpdates: Bool,
        allowPausedResume: Bool
    ) async {
        suppressBlockingOverlay = allowUserInteraction
        defer { suppressBlockingOverlay = false }
        let previouslyAppliedFilterIDs = appliedSelectedFilterIDs

        if prepareState {
            await MainActor.run { self.prepareApplyRunState() }
        }
        let pausedComponents: BlockingPauseComponents = allowPausedResume
            ? []
            : BlockingPauseStore.pausedComponents()
        let runSnapshot = activeApplySnapshot ?? ApplyRunSnapshot(
            filters: filterLists,
            configurations: filterConfigurations,
            selectedFilterIDs: selectedFilterIDs,
            customFilterKeys: customFilterKeys,
            disabledSites: effectiveFilterDisabledSites(),
            activeZapperRules: dataManager.getActiveZapperRulesByHost(),
            disabledZapperDomains: Set(dataManager.getDisabledZapperDomains())
        )

        // When both output-producing components are paused, keep the content blockers and
        // advanced engine inert. A userscript-only pause must still apply filter rules.
        if pausedComponents.contains(.filters)
            && pausedComponents.contains(.elementZapper)
            && !allowPausedResume {
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
            let cleanupSucceeded: Bool
            if cleared {
                cleanupSucceeded = await clearDownloadedStateForDeselectedRemoteFilters(
                    previouslyAppliedFilterIDs: previouslyAppliedFilterIDs
                )
            } else {
                cleanupSucceeded = false
            }
            await MainActor.run {
                self.lastRuleCount = 0
                self.ruleCountsByExtension.removeAll()
                self.extensionsApproachingLimit.removeAll()
                self.saveRuleCounts()
                self.isLoading = false
                self.showingApplyProgressSheet = !(cleared && cleanupSucceeded)
                if cleared && cleanupSucceeded {
                    self.lastApplySucceeded = true
                    self.persistUpgradeRebuildSignature()
                    self.clearFailedUpgradeRebuildSignature()
                    self.commitApplySnapshot(runSnapshot)
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

        if await failApplyIfCancelled() { return }

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

            let enabledFilters = pausedComponents.contains(.filters)
                ? []
                : runSnapshot.filters.filter { $0.isSelected }
            if !enabledFilters.isEmpty {
                let refreshResult = await filterUpdater.refreshFiltersIfNeeded(
                    enabledFilters, progressCallback: { prog in
                        await MainActor.run {
                            self.progress = prog * 0.1
                            self.applyProgressViewModel.updatePhaseProgress(Double(prog))
                        }
                        await Self.allowProgressUIRefresh()
                    }
                )
                let updatedFilters = refreshResult.updated

                await MainActor.run {
                    self.applyProgressViewModel.updateFilterUpdatesFound(updatedFilters.count)
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
            if !pausedComponents.contains(.userScripts),
               let userScriptManager = filterUpdater.userScriptManager {
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

        if await failApplyIfCancelled() { return }

        let allSelectedFilters = pausedComponents.contains(.filters)
            ? []
            : runSnapshot.filters.filter { $0.isSelected }
        // The snapshot preserves the user's selection, but its counts can predate the
        // metadata hydration/download above on the first apply.
        let refreshedSourceRuleCounts = Dictionary(
            uniqueKeysWithValues: filterLists.compactMap { filter in
                filter.sourceRuleCount.map { (filter.id, $0) }
            }
        )
        let generatedZapperRules = pausedComponents.contains(.elementZapper)
            ? []
            : ZapperContentBlockerRuleGenerator.generatedRules(
                from: runSnapshot.activeZapperRules
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
            let cleanupSucceeded: Bool
            if cleared {
                cleanupSucceeded = await clearDownloadedStateForDeselectedRemoteFilters(
                    previouslyAppliedFilterIDs: previouslyAppliedFilterIDs
                )
            } else {
                cleanupSucceeded = false
            }
            await MainActor.run {
                self.isLoading = false
                self.showingApplyProgressSheet = !(cleared && cleanupSucceeded)
                if cleared && cleanupSucceeded {
                    self.lastApplySucceeded = true
                    self.persistUpgradeRebuildSignature()
                    self.clearFailedUpgradeRebuildSignature()
                    self.commitApplySnapshot(runSnapshot)
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
            self.sourceRulesCount = allSelectedFilters.reduce(0) {
                $0 + (refreshedSourceRuleCounts[$1.id] ?? $1.sourceRuleCount ?? 0)
            } + generatedZapperRules.count

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

            self.applyProgressViewModel.updateConvertingDone(0)
        }

        // Collect advanced rules by target bundle ID (single storage)
        var advancedRulesByTarget: [String: String] = [:]  // bundleIdentifier -> advanced rules

        let ruleLimit = ContentBlockerService.safariContentBlockerRuleLimit
        let warningThreshold = Int(Double(ruleLimit) * 0.8)  // 80% threshold

        let disabledSites = runSnapshot.disabledSites
        if await failApplyIfCancelled() { return }
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
        if await failApplyIfCancelled() { return }
        let affinitySnapshot = await Task.detached(priority: .utility) {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value
            ) else {
                return SafariContentBlockerAffinitySnapshot(contentsByFilterID: [:])
            }

            return SafariContentBlockerAffinityProcessor.snapshot(
                for: orderedSelectedFilters,
                containerURL: containerURL
            )
        }.value

        await MainActor.run {
            self.applyProgressViewModel.updatePhaseCompletion(reading: true, converting: false)
        }

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
                #if os(iOS)
                if ApplyCancellation.isCancelled || Task.isCancelled {
                    return TargetConversionCompletion(
                        work: work,
                        outcome: nil,
                        failureDescription: LocalizedStrings.text(
                            "Apply cancelled to release file locks before suspension",
                            comment: "Apply pipeline suspension cancel"
                        ),
                        durationMs: Int(Date().timeIntervalSince(conversionStart) * 1000)
                    )
                }
                #endif
                #if os(iOS)
                let isConversionCancelled = {
                    ApplyCancellation.isCancelled || Task.isCancelled
                }
                #else
                let isConversionCancelled = { Task.isCancelled }
                #endif
                do {
                    let outcome = try ContentBlockerService.compileTargetRules(
                        filters: work.filters,
                        orderedSelectedFilters: orderedSelectedFilters,
                        affinitySnapshot: affinitySnapshot,
                        targetInfo: work.targetInfo,
                        allTargets: platformTargets,
                        disabledSites: disabledSites,
                        extraRulesText: work.extraRulesText,
                        groupIdentifier: groupIdentifier,
                        isCancelled: isConversionCancelled
                    )
                    return TargetConversionCompletion(
                        work: work,
                        outcome: outcome,
                        failureDescription: nil,
                        durationMs: Int(Date().timeIntervalSince(conversionStart) * 1000)
                    )
                } catch is CancellationError {
                    return TargetConversionCompletion(
                        work: work,
                        outcome: nil,
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
                #if os(iOS)
                if ApplyCancellation.isCancelled || Task.isCancelled {
                    return
                }
                #endif
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

        if let missingOutcomeTarget = platformTargets.first(where: { targetInfo in
            guard let completion = conversionCompletions[targetInfo] else { return true }
            return completion.outcome == nil && completion.failureDescription == nil
        }) {
            if await failApplyIfCancelled() { return }
            await failApplyRun(
                logMessage: LocalizedStrings.text("Failed to convert rules for blocker"),
                metadata: [
                    "blocker": missingOutcomeTarget.displayName,
                    "error": "Conversion returned no result.",
                ]
            )
            return
        }

        if await failApplyIfCancelled() { return }

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
                    outputChanged: conversionResult.outputChanged,
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
            self.applyProgressViewModel.updatePhaseCompletion(converting: true, reloading: false)
        }
        await ConcurrentLogManager.shared.info(
            .filterApply, LocalizedStrings.text("Conversion phase summary"),
            metadata: [
                "targets": "\(conversionMetrics.count)",
                "assignedFilters": "\(conversionMetrics.reduce(0) { $0 + $1.filterCount })",
                "cacheHits": "\(conversionMetrics.filter { $0.reusedCachedBase }.count)",
                "cacheMisses": "\(conversionMetrics.filter { !$0.reusedCachedBase }.count)",
                "changedOutputs": "\(conversionMetrics.filter(\.outputChanged).count)",
                "unchangedOutputs": "\(conversionMetrics.filter { !$0.outputChanged }.count)",
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
            self.applyProgressViewModel.updateStageDescription(
                LocalizedStrings.text("Reloading Safari extensions...", comment: "Apply pipeline stage")
            )
            self.applyProgressViewModel.updateProcessedCount(0, total: totalFiltersCount)
            self.applyProgressViewModel.updateReloadingDone(0)
            self.applyProgressViewModel.updateCurrentFilter("")
        }

        let reloadSummary = await reloadContentBlockers(platformTargets)
        let allReloadsSuccessful = reloadSummary.allSuccessful
        let activeReloads = reloadSummary.metrics.filter { !$0.skipped }
        let reloadDurationMs = reloadSummary.durationMs

        await MainActor.run {
            self.lastReloadTime = String(format: "%.2fs", Double(reloadDurationMs) / 1000)
        }

        let failedReloads = activeReloads.filter { !$0.success }
        let skippedReloads = reloadSummary.metrics.filter(\.skipped)
        let retriedReloads = activeReloads.filter { $0.attempts > 1 }
        let totalReloadAttempts = activeReloads.reduce(0) { $0 + $1.attempts }
        let reloadMetadata: [String: String] = [
            "targets": "\(reloadSummary.metrics.count)",
            "activeTargets": "\(activeReloads.count)",
            "failedTargets": "\(failedReloads.count)",
            "retriedTargets": "\(retriedReloads.count)",
            "totalAttempts": "\(totalReloadAttempts)",
            "avgAttempts": activeReloads.isEmpty ? "0" : String(
                format: "%.2f",
                Double(totalReloadAttempts) / Double(activeReloads.count)
            ),
            "reloadTime": await MainActor.run { self.lastReloadTime },
            "slowestTarget": activeReloads.max(by: { $0.durationMs < $1.durationMs })
                .map { "\($0.blockerName)@\($0.durationMs)ms" } ?? "n/a",
            "reloadDurationMs": "\(reloadDurationMs)",
            "failedNames": failedReloads.prefix(3).map(\.blockerName).joined(separator: ","),
            "skippedTargets": "\(skippedReloads.count)",
            "skippedNames": skippedReloads.map(\.blockerName).joined(separator: ","),
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

        // Build the combined filter engine after all content blockers are reloaded.
        if await failApplyIfCancelled() { return }

        await MainActor.run {
            self.progress = 0.9
            self.applyProgressViewModel.updatePhaseCompletion(reloading: true, saving: false)
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

                    try ContentBlockerService.publishCombinedFilterEngine(
                        combinedAdvancedRules: combinedAdvancedRules,
                        groupIdentifier: GroupIdentifier.shared.value
                    )
                }.value
            } else {
                await ConcurrentLogManager.shared.debug(
                    .filterApply, LocalizedStrings.text("No advanced rules found, clearing filter engine"), metadata: [:])
                try await Task.detached {
                    try ContentBlockerService.publishCombinedFilterEngine(
                        combinedAdvancedRules: "",
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

            self.applyProgressViewModel.updateStatistics(
                sourceRules: self.sourceRulesCount,
                safariRules: self.lastRuleCount,
                conversionTime: self.lastConversionTime,
                reloadTime: self.lastReloadTime,
                statusMessage: self.statusDescription,
                resultWarning: resultWarning
            )
            self.applyProgressViewModel.updateIsLoading(false)
        }

        let applySucceeded = await MainActor.run {
            allReloadsSuccessful && advancedEngineSucceeded && !self.hasError
        }
        if applySucceeded {
            // Cleanup is deliberately post-success: a failed conversion/reload/engine publish
            // must leave the previous downloadable baseline and validators intact.
            let cleanupSucceeded = await clearDownloadedStateForDeselectedRemoteFilters(
                previouslyAppliedFilterIDs: previouslyAppliedFilterIDs
            )
            if cleanupSucceeded {
                await MainActor.run {
                    self.lastApplySucceeded = true
                    self.persistUpgradeRebuildSignature()
                    self.clearFailedUpgradeRebuildSignature()
                    self.commitApplySnapshot(runSnapshot)
                }
            }
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
    /// an inert no-op rule list to every content blocker target, then reloads each target.
    /// Used both by the "no filters selected" apply path and by the global pause toggle.
    /// Returns `true` on success, `false` after reporting the failure via `failApplyRun`.
    func clearAllExtensionsAndEngine() async -> Bool {
        if await failApplyIfCancelled() { return false }

        let currentPlatform = self.currentPlatform

        do {
            let skippedNames = try await Task.detached { () throws -> [String] in
                let groupIdentifier = GroupIdentifier.shared.value
                try ContentBlockerService.publishCombinedFilterEngine(
                    combinedAdvancedRules: "",
                    groupIdentifier: groupIdentifier
                )
                _ = try RemoveParamDNRRuleGenerator.clearSavedRules(
                    groupIdentifier: groupIdentifier
                )

                let platformTargets = ContentBlockerTargetManager.shared.allTargets(
                    forPlatform: currentPlatform
                )
                var saveFailures: [String] = []

                for targetInfo in platformTargets {
                    let saveResult = try ContentBlockerService.saveContentBlockerIfChanged(
                        jsonRules: ContentBlockerService.inertContentBlockerRulesJSON,
                        groupIdentifier: groupIdentifier,
                        targetRulesFilename: targetInfo.rulesFilename
                    )
                    if saveResult.ruleCount != ContentBlockerService.inertContentBlockerRuleCount {
                        saveFailures.append(targetInfo.displayName)
                    }
                }

                if !saveFailures.isEmpty {
                    throw ApplyPipelineError.emptyRulesSaveFailed(
                        targetName: saveFailures.joined(separator: ", ")
                    )
                }

                var reloadFailures: [String] = []
                var skippedNames: [String] = []
                var reloadResults: [(ContentBlockerTargetInfo, ContentBlockerService.ReloadAttemptResult)] = []
                reloadResults.reserveCapacity(platformTargets.count)
                await boundedConcurrentForEach(platformTargets, maxConcurrent: {
                    #if os(macOS)
                    return 3
                    #else
                    return 1
                    #endif
                }(), operation: { targetInfo in
                    let reloadResult = await ContentBlockerService.reloadIfNeeded(
                        identifier: targetInfo.bundleIdentifier,
                        targetRulesFilename: targetInfo.rulesFilename,
                        groupIdentifier: groupIdentifier
                    )
                    return (targetInfo, reloadResult)
                }, onResult: { item in
                    reloadResults.append(item)
                })
                reloadResults.sort { $0.0.slot < $1.0.slot }
                for (targetInfo, result) in reloadResults {
                    if result.skipped {
                        skippedNames.append(targetInfo.displayName)
                    } else if !result.success {
                        reloadFailures.append(targetInfo.displayName)
                    }
                }

                if !reloadFailures.isEmpty {
                    throw ApplyPipelineError.emptyRulesReloadFailed(
                        targetName: reloadFailures.joined(separator: ", ")
                    )
                }
                return skippedNames
            }.value
            if !skippedNames.isEmpty {
                await ConcurrentLogManager.shared.info(
                    .filterApply,
                    LocalizedStrings.text("Process completed successfully"),
                    metadata: ["skippedTargets": skippedNames.joined(separator: ",")]
                )
            }
            return true
        } catch {
            await failApplyRun(
                logMessage: LocalizedStrings.text("Failed to clear extensions and advanced engine"),
                metadata: ["error": error.localizedDescription]
            )
            return false
        }
    }

    /// Sets the independently paused components. The primary Pause Blocking control calls
    /// this with `.all` or `[]`; clearing the selection runs the canonical resume apply.
    @discardableResult
    func setPausedComponents(_ components: BlockingPauseComponents) async -> Bool {
        let normalized = components.intersection(.all)
        if normalized.isEmpty {
            return await resumeBlocking()
        }

        let started = await performExclusiveApply { [self] in
            lastApplySucceeded = false
            if normalized == .all {
                BlockingPauseStore.setPaused(true)
            } else {
                BlockingPauseStore.setPausedComponents(normalized)
            }
            UserScriptManager.invalidateDocumentStartExecutionCache()
            if normalized.contains(.elementZapper) {
                ZapperRuleManager.notifySafariRulesChanged()
            }
            await MainActor.run {
                self.hasError = false
                self.pausedComponents = normalized
                self.isBlockingPaused = true
                self.statusDescription = LocalizedStrings.text(
                    "Pausing blocking...",
                    comment: "Apply pipeline pause status"
                )
                self.applyProgressViewModel.updateStageDescription(
                    LocalizedStrings.text("Pausing blocking...", comment: "Apply pipeline stage")
                )
                self.applyProgressViewModel.updatePhaseCompletion(updating: true, scripts: true)
            }

            if normalized == .all {
                let cleared = await self.clearAllExtensionsAndEngine()
                await MainActor.run {
                    self.lastRuleCount = 0
                    self.ruleCountsByExtension.removeAll()
                    self.extensionsApproachingLimit.removeAll()
                    self.saveRuleCounts()
                    self.isLoading = false
                    self.showingApplyProgressSheet = false
                    if cleared {
                        self.lastApplySucceeded = true
                        self.persistUpgradeRebuildSignature()
                        self.clearFailedUpgradeRebuildSignature()
                        self.markCurrentStateApplied()
                        self.statusDescription = LocalizedStrings.text(
                            "Blocking paused", comment: "Apply pipeline pause status"
                        )
                    }
                }
            } else {
                await applyChangesUnlocked(
                    allowUserInteraction: false,
                    prepareState: true,
                    skipPreApplyUpdates: false,
                    allowPausedResume: false
                )
            }
        }

        let succeeded = started && lastApplySucceeded && !hasError
        if started && !succeeded {
            await failClosedAfterStartedPauseTransition()
        }
        return succeeded
    }

    private func failClosedAfterStartedPauseTransition() async {
        BlockingPauseStore.setPaused(true)
        UserScriptManager.invalidateDocumentStartExecutionCache()
        await MainActor.run {
            self.pausedComponents = .all
            self.isBlockingPaused = true
            if self.statusDescription.isEmpty {
                self.statusDescription = LocalizedStrings.text(
                    "Failed",
                    comment: "Apply pipeline pause failure status"
                )
            }
        }
    }

    @discardableResult
    func setBlockingPaused(_ paused: Bool) async -> Bool {
        await setPausedComponents(paused ? .all : [])
    }

    private func resumeBlocking() async -> Bool {
        guard !BlockingPauseStore.pausedComponents().isEmpty else {
            await MainActor.run {
                self.pausedComponents = []
                self.isBlockingPaused = false
            }
            return true
        }

        let started = await performExclusiveApply { [self] in
            lastApplySucceeded = false
            BlockingPauseStore.setResumeApplying()
            // Keep blocking fail-closed in shared storage, but let SwiftUI paint the
            // requested off state before the apply pipeline occupies the main actor.
            BlockingPauseStore.setPaused(true)
            UserScriptManager.invalidateDocumentStartExecutionCache()
            await MainActor.run {
                self.pausedComponents = []
                self.isBlockingPaused = false
                self.statusDescription = LocalizedStrings.text(
                    "Applying filters...\n(This may take a while)",
                    comment: "Apply pipeline resume status"
                )
            }
            await Task.yield()
            await applyChangesUnlocked(
                allowUserInteraction: false,
                prepareState: true,
                skipPreApplyUpdates: false,
                allowPausedResume: true
            )

            let succeeded = lastApplySucceeded && !hasError
            if succeeded {
                BlockingPauseStore.setPaused(false)
                UserScriptManager.invalidateDocumentStartExecutionCache()
                ZapperRuleManager.notifySafariRulesChanged()
                await MainActor.run {
                    self.pausedComponents = []
                    self.isBlockingPaused = false
                    self.statusDescription = LocalizedStrings.text(
                        "Blocking resumed", comment: "Apply pipeline resume status"
                    )
                }
            } else {
                BlockingPauseStore.setPaused(true)
                await MainActor.run {
                    self.pausedComponents = .all
                    self.isBlockingPaused = true
                    if self.statusDescription.isEmpty {
                        self.statusDescription = LocalizedStrings.text(
                            "Failed to resume blocking.",
                            comment: "Apply pipeline resume failure status"
                        )
                    }
                }
            }
        }
        return started && lastApplySucceeded && !BlockingPauseStore.isPaused()
    }

    func prepareApplyRunState() {
        captureApplySnapshot()
        lastApplySucceeded = false
        isLoading = true
        hasError = false
        progress = 0
        statusDescription = LocalizedStrings.text("Checking for updates...", comment: "Apply pipeline status")

        applyProgressViewModel.beginProgressRun()

        sourceRulesCount = 0
        processedFiltersCount = 0
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
        let outputChanged: Bool
        let durationMs: Int
    }


    struct TargetReloadMetrics {
        let blockerName: String
        let success: Bool
        let skipped: Bool
        let attempts: Int
        let durationMs: Int
    }

    struct ReloadPhaseSummary {
        let allSuccessful: Bool
        let metrics: [TargetReloadMetrics]
        let durationMs: Int
    }




    func reloadContentBlockers(_ targets: [ContentBlockerTargetInfo]) async -> ReloadPhaseSummary {
        let totalCount = targets.count
        let reloadStartTime = Date()

        let groupIdentifier = GroupIdentifier.shared.value
        var collected: [(target: ContentBlockerTargetInfo, reload: ContentBlockerService.ReloadAttemptResult)] = []
        collected.reserveCapacity(targets.count)
        var completed = 0

        await boundedConcurrentForEach(targets, maxConcurrent: {
            #if os(macOS)
            return 3
            #else
            return 1
            #endif
        }(), operation: { target in
            let reload = await ContentBlockerService.reloadIfNeeded(
                identifier: target.bundleIdentifier,
                targetRulesFilename: target.rulesFilename,
                groupIdentifier: groupIdentifier
            )
            return (target, reload)
        }, onResult: { item in
            collected.append(item)
            completed += 1
            let name = item.0.displayName
            await MainActor.run {
                self.processedFiltersCount = completed
                self.applyProgressViewModel.updateCurrentFilter(name)
                self.applyProgressViewModel.updateReloadingDone(completed)
                self.progress =
                    0.7 + (Float(completed) / Float(max(1, totalCount)) * 0.2)
            }
            await Self.allowProgressUIRefresh()
            _ = await self.failApplyIfCancelled()
        })

        // Preserve slot order for stable logging/UI.
        let orderedResults = collected.sorted { $0.target.slot < $1.target.slot }
        let reloadDurationMs = collected.contains { !$0.reload.skipped }
            ? Int(Date().timeIntervalSince(reloadStartTime) * 1000)
            : 0

        var allSuccessful = true
        var metrics: [TargetReloadMetrics] = []
        var failedNames: [String] = []

        for result in orderedResults {
            let name = result.target.displayName
            if !result.reload.success {
                failedNames.append(name)
            }
            metrics.append(
                TargetReloadMetrics(
                    blockerName: name,
                    success: result.reload.success,
                    skipped: result.reload.skipped,
                    attempts: result.reload.attempts,
                    durationMs: result.reload.durationMs
                )
            )
            allSuccessful = allSuccessful && result.reload.success
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

        return ReloadPhaseSummary(
            allSuccessful: allSuccessful,
            metrics: metrics,
            durationMs: reloadDurationMs
        )
    }

    static func allowProgressUIRefresh() async {
        #if os(iOS)
        if ApplyCancellation.isCancelled || Task.isCancelled {
            return
        }
        do {
            try await Task.sleep(nanoseconds: 16_000_000)
            try Task.checkCancellation()
        } catch {
            return
        }
        #else
        try? await Task.sleep(nanoseconds: 16_000_000)
        #endif
    }

}
