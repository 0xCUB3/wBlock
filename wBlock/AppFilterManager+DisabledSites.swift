import Foundation
import wBlockCoreService

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
                    "Disabled sites monitor unavailable (no protobuf data directory)",
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
                    "Failed to start disabled sites monitor",
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
            await ConcurrentLogManager.shared.info(
                .whitelist, "Disabled sites changed, fast rebuilding content blockers",
                metadata: [
                    "previousCount": "\(lastKnownDisabledSites.count)",
                    "newCount": "\(currentDisabledSites.count)",
                ])

            lastKnownDisabledSites = currentDisabledSites
            // Only rebuild if we have applied filters (don't rebuild on startup)
            if !hasUnappliedChanges && lastRuleCount > 0 {
                await fastApplyDisabledSitesChanges()
            }
        }
    }

    /// Fast rebuild for disabled sites changes only - skips SafariConverterLib conversion
    func fastApplyDisabledSitesChanges() async {
        await MainActor.run {
            self.isLoading = true
            self.statusDescription = LocalizedStrings.text(
                "Updating disabled sites...",
                comment: "Disabled sites update status"
            )
        }
        let disabledSites = effectiveFilterDisabledSites()
        await ConcurrentLogManager.shared.info(
            .whitelist, "Fast applying disabled sites changes without full conversion",
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
                    let result = try ContentBlockerService.fastUpdateDisabledSites(
                        groupIdentifier: GroupIdentifier.shared.value,
                        targetRulesFilename: targetInfo.rulesFilename,
                        disabledSites: disabledSites
                    )
                    if result.safariRulesCount > 0 {
                        nonEmptyTargets.append(targetInfo)
                    }
                } catch {
                    failureCount += 1
                }
            }
            return (nonEmptyTargets, failureCount)
        }.value
        let targetsToReload = updateResult.0
        let updateFailureCount = updateResult.1

        let overallReloadStartTime = Date()
        let successCount = await Self.reloadDisabledSitesTargetsInParallel(targetsToReload)
        let skippedCount = max(platformTargets.count - targetsToReload.count, 0)

        let reloadTime = String(format: "%.2fs", Date().timeIntervalSince(overallReloadStartTime))

        await MainActor.run {
            self.lastReloadTime = reloadTime
            self.lastFastUpdateTime = reloadTime
            self.fastUpdateCount += 1
            self.isLoading = false

            if updateFailureCount == 0, successCount == targetsToReload.count {
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
                    successCount,
                    targetsToReload.count + updateFailureCount,
                    reloadTime
                )
            }
        }

        await ConcurrentLogManager.shared.info(
            .whitelist, "Fast disabled sites update completed",
            metadata: [
                "successCount": "\(successCount)",
                "totalCount": "\(targetsToReload.count)",
                "updateFailureCount": "\(updateFailureCount)",
                "skippedCount": "\(skippedCount)",
                "reloadTime": reloadTime,
            ])
    }

    nonisolated private static func reloadDisabledSitesTargetsInParallel(_ targets: [ContentBlockerTargetInfo]) async -> Int {
        var successCount = 0

        await boundedConcurrentForEach(targets, maxConcurrent: {
            #if os(macOS)
            return 3
            #else
            return 1
            #endif
        }(), operation: { target in
            await ContentBlockerService.reloadWithRetry(identifier: target.bundleIdentifier).success
        }, onResult: { success in
            if success { successCount += 1 }
        })

        return successCount
    }
}
