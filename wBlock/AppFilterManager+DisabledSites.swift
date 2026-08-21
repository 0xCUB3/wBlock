import Foundation
import wBlockCoreService

@MainActor
private var disabledSitesApplyRetryTask: Task<Void, Never>?

extension AppFilterManager {
    /// Sets up an observer to automatically rebuild content blockers when disabled sites change
    func setupDisabledSitesObserver() {
        // Store the last known disabled sites to detect changes.
        lastKnownDisabledSites = effectiveFilterDisabledSites()


        disabledSitesDirectoryMonitor.stop()
        

        guard let directoryURL = dataManager.protobufDataDirectoryURL() else {
            Task {
                await ConcurrentLogManager.shared.warning(
                    .whitelist,
                    LocalizedStrings.text("Disabled sites monitor unavailable (no protobuf data directory)"),
                    metadata: [:]
                )
            }
            return
        }

        guard disabledSitesDirectoryMonitor.start(directoryURL: directoryURL, onChange: { [weak self] in
            Task { @MainActor [weak self] in
                await self?.checkForDisabledSitesChanges()
            }
        }) else {
            Task {
                await ConcurrentLogManager.shared.warning(
                    .whitelist,
                    LocalizedStrings.text("Failed to start disabled sites monitor"),
                    metadata: ["directory": directoryURL.path]
                )
            }
            return
        }
    }

    /// Returns the normalized union used only for content filtering.
    func effectiveFilterDisabledSites() -> [String] {
        DisabledSitesNormalizer.effectiveFilterDisabledDomains(
            master: dataManager.disabledSites,
            filterOnly: dataManager.filterDisabledSites
        )
    }

    /// Checks for changes in disabled sites and triggers fast rebuild if needed
    @MainActor
    func checkForDisabledSitesChanges() async {
        // Only reload protobuf data when the shared file actually changed
        _ = await dataManager.refreshFromDiskIfModified()

        let currentDisabledSites = effectiveFilterDisabledSites()

        if currentDisabledSites != lastKnownDisabledSites {
            if ContentBlockerService.isDisabledSitesApplyInProgress(
                groupIdentifier: GroupIdentifier.shared.value
            ) {
                scheduleDisabledSitesApplyRetry()
                return
            }

            await ConcurrentLogManager.shared.info(
                .whitelist, LocalizedStrings.text("Disabled sites changed, fast rebuilding content blockers"),
                metadata: [
                    "previousCount": "\(lastKnownDisabledSites.count)",
                    "newCount": "\(currentDisabledSites.count)",
                ])

            // Only rebuild if we have applied filters (don't rebuild on startup). Keep the
            // old snapshot until the complete fast transaction succeeds so failures stay dirty.
            if !hasUnappliedChanges && lastRuleCount > 0 {
                await fastApplyDisabledSitesChanges()
            } else {
                lastKnownDisabledSites = currentDisabledSites
            }
        }
    }

    /// Retries the directory-monitor check after an extension-owned site toggle
    /// has had time to finish its Safari reload. Replacing the task coalesces
    /// repeated filesystem events without marking the app state dirty.
    private func scheduleDisabledSitesApplyRetry() {
        disabledSitesApplyRetryTask?.cancel()
        disabledSitesApplyRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.checkForDisabledSitesChanges()
        }
    }

    /// Fast rebuild for disabled sites changes only - skips SafariConverterLib conversion.
    /// It uses the same exclusivity gate as the full apply pipeline.
    func fastApplyDisabledSitesChanges() async {
        let started = await performExclusiveApply {
            _ = await self.performFastDisabledSitesApply()
        }
        if !started {
            // The active full apply will schedule one follow-up from the shared gate’s
            // defer path. Avoid recursive polling while a long conversion is running.
            hasUnappliedChanges = true
            lastApplySucceeded = false
            scheduleAutoApplyDebounce()
        }
    }

    private func performFastDisabledSitesApply() async -> Bool {
        let appliedSnapshot = effectiveFilterDisabledSites()
        await MainActor.run {
            self.isLoading = true
            self.statusDescription = LocalizedStrings.text(
                "Updating disabled sites...",
                comment: "Disabled sites update status"
            )
        }
        let disabledSites = effectiveFilterDisabledSites()
        await ConcurrentLogManager.shared.info(
            .whitelist, LocalizedStrings.text("Fast applying disabled sites changes without full conversion"),
            metadata: [:])

        // Get all platform targets that need updating
        let currentPlatform = self.currentPlatform
        let platformTargets = await Task.detached {
            ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        }.value


        let updateResult = await Task.detached { () -> ([ContentBlockerTargetInfo], Int) in
            var nonEmptyTargets: [ContentBlockerTargetInfo] = []
            var failureCount = 0
            for targetInfo in platformTargets {
                do {
                    _ = try ContentBlockerService.fastUpdateDisabledSites(
                        groupIdentifier: GroupIdentifier.shared.value,
                        targetRulesFilename: targetInfo.rulesFilename,
                        disabledSites: disabledSites
                    )
                    nonEmptyTargets.append(targetInfo)
                } catch {
                    failureCount += 1
                }
            }
            return (nonEmptyTargets, failureCount)
        }.value
        let targetsToReload = updateResult.0
        let updateFailureCount = updateResult.1

        let reloadSummary = await Self.reloadDisabledSitesTargetsInParallel(targetsToReload)
        let skippedCount = reloadSummary.skippedTargets
        let reloadTime = String(format: "%.2fs", Double(reloadSummary.reloadDurationMs) / 1000)

        let succeeded = updateFailureCount == 0 && reloadSummary.failedTargets == 0

        await MainActor.run {
            self.lastReloadTime = reloadTime
            self.lastFastUpdateTime = reloadTime
            self.fastUpdateCount += 1
            self.isLoading = false
            // Do not clear the dirty/error state on a partial update. The directory monitor
            // will retry because lastKnownDisabledSites is advanced only on success.
            self.hasError = !succeeded
            self.lastApplySucceeded = succeeded
            if !succeeded {
                self.hasUnappliedChanges = true
            }

            if succeeded {
                self.statusDescription = LocalizedStrings.format(
                    "Disabled sites updated successfully in %@ (fast update #%d)",
                    comment: "Disabled sites update success status",
                    reloadTime,
                    self.fastUpdateCount
                )
            } else {
                self.statusDescription = LocalizedStrings.format(
                    "Updated %d/%d extensions in %@",
                    comment: "Disabled sites partial update status",
                    reloadSummary.reloadedTargets + reloadSummary.skippedTargets,
                    targetsToReload.count + updateFailureCount,
                    reloadTime
                )
            }
        }

        await ConcurrentLogManager.shared.info(
            .whitelist, LocalizedStrings.text("Fast disabled sites update completed"),
            metadata: [
                "successCount": "\(reloadSummary.reloadedTargets)",
                "totalCount": "\(targetsToReload.count)",
                "updateFailureCount": "\(updateFailureCount)",
                "skippedCount": "\(skippedCount)",
                "skippedNames": reloadSummary.skippedNames.joined(separator: ","),
                "failedCount": "\(reloadSummary.failedTargets)",
                "reloadTime": reloadTime,
            ])

        if succeeded {
            lastKnownDisabledSites = appliedSnapshot
            // If a newer snapshot arrived during the update, immediately schedule one
            // follow-up rather than publishing the intermediate snapshot as current.
            if effectiveFilterDisabledSites() != appliedSnapshot {
                hasUnappliedChanges = true
                scheduleAutoApplyDebounce()
            }
        }
        return succeeded
    }

    nonisolated private static func reloadDisabledSitesTargetsInParallel(_ targets: [ContentBlockerTargetInfo]) async -> (
        reloadedTargets: Int,
        skippedTargets: Int,
        failedTargets: Int,
        reloadDurationMs: Int,
        skippedNames: [String]
    ) {
        var reloadedTargets = 0
        var skippedTargets = 0
        var failedTargets = 0
        var skippedNames: [String] = []
        let groupIdentifier = GroupIdentifier.shared.value
        let reloadStartTime = Date()

        await boundedConcurrentForEach(targets, maxConcurrent: {
            #if os(macOS)
            return 3
            #else
            return 1
            #endif
        }(), operation: { target in
            let result = await ContentBlockerService.reloadIfNeeded(
                identifier: target.bundleIdentifier,
                targetRulesFilename: target.rulesFilename,
                groupIdentifier: groupIdentifier
            )
            return (target, result)
        }, onResult: { item in
            let (target, result) = item
            if result.skipped {
                skippedTargets += 1
                skippedNames.append(target.displayName)
            } else if result.success {
                reloadedTargets += 1
            } else {
                failedTargets += 1
            }
        })

        let reloadDurationMs = reloadedTargets + failedTargets > 0
            ? Int(Date().timeIntervalSince(reloadStartTime) * 1000)
            : 0
        return (reloadedTargets, skippedTargets, failedTargets, reloadDurationMs, skippedNames)
    }
}
