import Foundation
import wBlockCoreService

extension AppFilterManager {
    /// Rules Safari accepts across every content blocker slot on this platform.
    var safariRuleCapacity: Int {
        ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform).count
            * ContentBlockerService.safariContentBlockerRuleLimit
    }

    var safariRuleCapacityFraction: Double {
        let capacity = safariRuleCapacity
        return capacity > 0 ? min(Double(lastRuleCount) / Double(capacity), 1.0) : 0.0
    }

    /// Counted here, off the main thread, from the blocker files on disk, so Rule
    /// Capacity opens with its Rule Types already filled in (#999). A newer request
    /// supersedes one still reading, so a slow load cannot overwrite a newer result.
    /// Call it only at a commit point: an apply writes the files before Safari reloads
    /// them, so a read in between would show rules Safari does not hold yet.
    func refreshAppliedRuleCounts() {
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        appliedRuleCountsRequest += 1
        let request = appliedRuleCountsRequest
        Task { @MainActor in
            let loaded = await Task.detached(priority: .utility) {
                AppliedRuleCounts.load(targets: targets, groupIdentifier: GroupIdentifier.shared.value)
            }.value
            guard request == appliedRuleCountsRequest else { return }
            if appliedRuleCounts != loaded { appliedRuleCounts = loaded }
        }
    }

    /// Reads the stored totals and per-blocker counts into memory. Runs at launch and
    /// on every store save, so a rebuild another process finished shows up without a
    /// relaunch. Skipped while this app applies or auto-updates. While the last run's counts
    /// are unsaved, a store revision other than the refused one is adopted, so a later
    /// helper rebuild replaces them.
    func refreshRuleCountsFromStore() {
        let revision = dataManager.ruleCountsRevision
        guard ruleCountsSync.shouldAdopt(
            storeRevision: revision,
            runInProgress: isApplyInFlight || isAutoUpdateRunning
        ) else { return }

        // Stored keys may be legacy category names or (new) bundle identifiers.
        var counts: [String: Int] = [:]
        for (categoryKey, count) in dataManager.ruleCountsByCategory {
            if ContentBlockerTargetManager.shared.targetInfo(forBundleIdentifier: categoryKey, platform: currentPlatform) != nil {
                counts[categoryKey] = Int(count)
                continue
            }

            if let category = FilterListCategory(rawValue: categoryKey),
               let legacyBundleID = legacyBundleIdentifier(for: category) {
                if counts[legacyBundleID] == nil {
                    counts[legacyBundleID] = Int(count)
                }
            }
        }

        var approaching: Set<String> = []
        for identifierOrCategory in dataManager.categoriesApproachingLimit {
            if ContentBlockerTargetManager.shared.targetInfo(forBundleIdentifier: identifierOrCategory, platform: currentPlatform) != nil {
                approaching.insert(identifierOrCategory)
                continue
            }
            if let category = FilterListCategory(rawValue: identifierOrCategory),
               let legacyBundleID = legacyBundleIdentifier(for: category) {
                approaching.insert(legacyBundleID)
            }
        }

        let total = dataManager.lastRuleCount
        if total != lastRuleCount { lastRuleCount = total }
        if counts != ruleCountsByExtension { ruleCountsByExtension = counts }
        if approaching != extensionsApproachingLimit { extensionsApproachingLimit = approaching }

        // The breakdown reads the blocker files, so it reloads whenever the store moved on.
        ruleCountsSync.matched(storeRevision: revision)
        refreshAppliedRuleCounts()
    }

    /// The app can be suspended while a run in another process writes the store,
    /// so reading from disk on foreground catches up with what the directory monitor missed.
    func refreshRuleCountsOnForeground() async {
        _ = await dataManager.refreshFromDiskIfModified()
        refreshRuleCountsFromStore()
        await adoptPersistedDownloadMetadata()
    }

    /// Commits the in-memory counts to the store. Callers await it, so the store leads
    /// the in-memory state before an apply clears its in-flight guard. A refused commit is
    /// logged and marks the counts unsaved: they stay on screen, because they are what
    /// Safari loaded, and the store is not read back until a later commit succeeds.
    func saveRuleCounts() async {
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
        let saved = await dataManager.updateAppliedRuleCounts(
            countsByBundleIdentifier: ruleCountsByExtension,
            approachingIdentifiers: extensionsApproachingLimit,
            targets: targets
        )
        // The blocker files are the loaded rules at this point, so the breakdown reloads either way.
        refreshAppliedRuleCounts()
        if saved {
            ruleCountsSync.matched(storeRevision: dataManager.ruleCountsRevision)
            return
        }
        // A refusal can still have reached disk (the version write failed after the data write).
        // Recording the revision first and reading the store back second lets the read show it.
        ruleCountsSync.refused(storeRevision: dataManager.ruleCountsRevision)
        _ = await dataManager.refreshFromDiskIfModified()
        refreshRuleCountsFromStore()
        await ConcurrentLogManager.shared.error(.filterApply, "Failed to save rule counts")
    }

    func legacyBundleIdentifier(for category: FilterListCategory) -> String? {
        let slot: Int?
        switch category {
        case .ads:
            slot = 1
        case .privacy:
            slot = 2
        case .security, .annoyances, .multipurpose:
            slot = 3
        case .foreign, .experimental:
            slot = 4
        case .custom:
            slot = 5
        default:
            slot = nil
        }

        guard let slot = slot else { return nil }
        return ContentBlockerTargetManager.shared
            .allTargets(forPlatform: currentPlatform)
            .first { $0.slot == slot }?
            .bundleIdentifier
    }
}
