import Foundation
import wBlockCoreService

extension AppFilterManager {
    /// Sets up an observer to automatically rebuild content blockers when disabled sites change
    func setupDisabledSitesObserver() {
        // Store the last known disabled sites to detect changes.
        lastKnownDisabledSites = dataManager.disabledSites

        disabledSitesDirectoryMonitor?.cancel()
        disabledSitesDirectoryMonitor = nil
        pendingDisabledSitesCheckTask?.cancel()
        pendingDisabledSitesCheckTask = nil

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

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Task {
                await ConcurrentLogManager.shared.warning(
                    .whitelist,
                    "Failed to start disabled sites monitor",
                    metadata: ["directory": directoryURL.path]
                )
            }
            return
        }

        disabledSitesDirectoryFileDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend],
            queue: disabledSitesMonitorQueue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.pendingDisabledSitesCheckTask?.cancel()
            var task: Task<Void, Never>?
            task = Task { @MainActor [weak self] in
                defer {
                    if let self, let task, self.pendingDisabledSitesCheckTask == task {
                        self.pendingDisabledSitesCheckTask = nil
                    }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                await self.checkForDisabledSitesChanges()
            }
            self.pendingDisabledSitesCheckTask = task
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.disabledSitesDirectoryFileDescriptor >= 0 {
                close(self.disabledSitesDirectoryFileDescriptor)
                self.disabledSitesDirectoryFileDescriptor = -1
            }
        }

        disabledSitesDirectoryMonitor = source
        source.resume()
    }

    /// Checks for changes in disabled sites and triggers fast rebuild if needed
    @MainActor
    func checkForDisabledSitesChanges() async {
        // Only reload protobuf data when the shared file actually changed
        _ = await dataManager.refreshFromDiskIfModified()

        let currentDisabledSites = dataManager.disabledSites

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
            self.statusDescription = "Updating disabled sites..."
        }

        await ConcurrentLogManager.shared.info(
            .whitelist, "Fast applying disabled sites changes without full conversion",
            metadata: [:])

        // Get all platform targets that need updating
        let currentPlatform = self.currentPlatform
        let platformTargets = await Task.detached {
            ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        }.value

        // Capture disabled sites on MainActor
        let disabledSites = dataManager.disabledSites

        let targetsToReload = await Task.detached { () -> [ContentBlockerTargetInfo] in
            var nonEmptyTargets: [ContentBlockerTargetInfo] = []
            for targetInfo in platformTargets {
                let result = ContentBlockerService.fastUpdateDisabledSites(
                    groupIdentifier: GroupIdentifier.shared.value,
                    targetRulesFilename: targetInfo.rulesFilename,
                    disabledSites: disabledSites
                )
                if result.safariRulesCount > 0 {
                    nonEmptyTargets.append(targetInfo)
                }
            }
            return nonEmptyTargets
        }.value

        let overallReloadStartTime = Date()
        let successCount = await Self.reloadDisabledSitesTargetsInParallel(targetsToReload)
        let skippedCount = max(platformTargets.count - targetsToReload.count, 0)

        let reloadTime = String(format: "%.2fs", Date().timeIntervalSince(overallReloadStartTime))

        await MainActor.run {
            self.lastReloadTime = reloadTime
            self.lastFastUpdateTime = reloadTime
            self.fastUpdateCount += 1
            self.isLoading = false

            if successCount == targetsToReload.count {
                self.statusDescription =
                    "✅ Disabled sites updated successfully in \(reloadTime) (fast update #\(self.fastUpdateCount))"
            } else {
                self.statusDescription =
                    "⚠️ Updated \(successCount)/\(targetsToReload.count) extensions in \(reloadTime)"
            }
        }

        await ConcurrentLogManager.shared.info(
            .whitelist, "Fast disabled sites update completed",
            metadata: [
                "successCount": "\(successCount)",
                "totalCount": "\(targetsToReload.count)",
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
