import Combine
import Foundation
import wBlockCoreService

// Two ProtobufDataManager instances share one data directory: `helper` is the
// auto-update writer, `app` is an open app that must see its completion.
@main
@MainActor
struct AutoUpdateRuleCountTests {
    static func main() async throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-auto-update-rule-counts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let groupIdentifier = "group.wblock.test.rulecounts.\(UUID().uuidString.prefix(8))"
        CosmeticFilteringPreference.setEnabled(false, groupIdentifier: groupIdentifier)

        let targets = Array(ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS).prefix(2))
        expect(targets.count == 2, "test needs two blocker targets")
        let (blockerA, blockerB) = (targets[0], targets[1])

        let listA = filter("a", updated: 1_000)
        let listB = filter("b", updated: 1_000)
        try write("||a1.example^\n||a2.example^\n||a3.example^\n", for: listA, in: container)
        try write("||b1.example^\n", for: listB, in: container)
        let outcomeA = try compile([listA], target: blockerA, groupIdentifier: groupIdentifier, container: container)
        let outcomeB = try compile([listB], target: blockerB, groupIdentifier: groupIdentifier, container: container)
        expect(outcomeA.safariRulesCount != outcomeB.safariRulesCount, "targets must have distinct counts")
        let outcomes = [
            blockerA.bundleIdentifier: outcomeA,
            blockerB.bundleIdentifier: outcomeB,
        ]
        let newTotal = outcomeA.safariRulesCount + outcomeB.safariRulesCount

        let dataDirectory = container.appendingPathComponent("data", isDirectory: true)
        let app = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dataDirectory)
        await app.loadData()

        // The last applied state, which a failed rebuild must leave in place.
        let previousCounts = [blockerA.bundleIdentifier: 900, blockerB.bundleIdentifier: 800]
        await app.updateAppliedRuleCounts(
            countsByBundleIdentifier: previousCounts, approachingIdentifiers: [], targets: targets
        )
        let previousTotal = 900 + 800
        expect(app.lastRuleCount == previousTotal, "seeded total must be stored")
        await app.saveDataImmediately()

        let helper = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dataDirectory)
        await helper.loadData()

        // A rebuild that did not produce every blocker's output stores nothing.
        let unfinished = [blockerA.bundleIdentifier: outcomeA]
        let recordedUnfinished = await SharedAutoUpdateManager.recordRebuiltRuleCounts(
            targets: targets, outcomes: unfinished, dataManager: helper
        )
        expect(!recordedUnfinished, "an unfinished rebuild must not record counts")
        expectEqual(helper.lastRuleCount, previousTotal, "failed rebuild must preserve the stored total")
        expectEqual(helper.ruleCountsByCategory[blockerA.bundleIdentifier], Int32(900),
                    "failed rebuild must preserve the per-blocker count")

        // A finished rebuild records what the blockers now hold, and the open app sees it.
        var appSawSave = false
        let saveObserver = app.didSaveData.sink { appSawSave = true }
        let recorded = await SharedAutoUpdateManager.recordRebuiltRuleCounts(
            targets: targets, outcomes: outcomes, dataManager: helper
        )
        expect(recorded, "a finished auto-update rebuild must record its Safari counts")
        expectEqual(helper.lastRuleCount, newTotal, "helper total must be the sum of the blockers' counts")

        let appChanged = await app.refreshFromDiskIfModified()
        expect(appChanged, "open app must detect the auto-update's write")
        expect(appSawSave, "open app must publish the external save so its UI can refresh")
        expectEqual(app.lastRuleCount, newTotal, "open app must read the new total from disk")
        expectEqual(app.ruleCountsByCategory[blockerA.bundleIdentifier], Int32(outcomeA.safariRulesCount),
                    "open app must read the blocker A count")
        expectEqual(app.ruleCountsByCategory[blockerB.bundleIdentifier], Int32(outcomeB.safariRulesCount),
                    "open app must read the blocker B count")

        let relaunched = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dataDirectory)
        await relaunched.loadData()
        expectEqual(relaunched.lastRuleCount, newTotal, "a relaunch must read the recorded total")
        withExtendedLifetime(saveObserver) {}

        // A second rebuild in the same second with the same total and a different split.
        // The whole-second stamp can repeat here; the revision must still move, and an open
        // app must see it through the disk refresh.
        let revisionBeforeSplit = helper.ruleCountsRevision
        await helper.updateAppliedRuleCounts(
            countsByBundleIdentifier: [blockerA.bundleIdentifier: 5, blockerB.bundleIdentifier: newTotal - 5],
            approachingIdentifiers: [], targets: targets
        )
        await helper.saveDataImmediately()
        expectEqual(helper.ruleCountsRevision, revisionBeforeSplit + 1, "every count write must advance the revision")
        expectEqual(helper.lastRuleCount, newTotal, "a same-total rewrite keeps the total")
        let splitVisible = await app.refreshFromDiskIfModified()
        expect(splitVisible, "open app must detect a same-total rewrite")
        expectEqual(app.ruleCountsRevision, helper.ruleCountsRevision, "open app must read the new revision")
        expectEqual(app.ruleCountsByCategory[blockerA.bundleIdentifier], Int32(5),
                    "open app must read the split written by the same-total rewrite")

        // A pause or an empty selection leaves only inert placeholder rules, so the store must
        // read zero everywhere, as the app's own clear does, and an open app must follow it.
        let clearedRecorded = await SharedAutoUpdateManager.recordClearedRuleCounts(targets: targets, dataManager: helper)
        expect(clearedRecorded, "a cleared rebuild must record its zero counts")
        expectEqual(helper.lastRuleCount, 0, "cleared outputs must store a zero total")
        expectEqual(helper.ruleCountsByCategory[blockerA.bundleIdentifier], Int32(0),
                    "cleared outputs must store a zero per-blocker count")
        _ = await app.refreshFromDiskIfModified()
        expectEqual(app.lastRuleCount, 0, "open app must read the cleared total")

        // The caller's flags are stored as given. A truncated blocker at the threshold is
        // excluded by the caller, so it must not come back flagged.
        let threshold = ContentBlockerService.approachingRuleLimitThreshold
        expectEqual(threshold, 120_000, "approaching threshold must be 80% of Safari's limit")
        await helper.updateAppliedRuleCounts(
            countsByBundleIdentifier: [blockerA.bundleIdentifier: threshold, blockerB.bundleIdentifier: 5],
            approachingIdentifiers: [], targets: targets
        )
        expectEqual(helper.categoriesApproachingLimit, [],
                    "a blocker the caller did not flag must not be flagged by the store")
        await helper.updateAppliedRuleCounts(
            countsByBundleIdentifier: [blockerA.bundleIdentifier: threshold, blockerB.bundleIdentifier: 5],
            approachingIdentifiers: [blockerA.bundleIdentifier], targets: targets
        )
        expectEqual(helper.categoriesApproachingLimit, [blockerA.bundleIdentifier],
                    "the flagged blocker must be stored as flagged")

        try await checkConcurrentWritersKeepRevisionsUnique(targets: targets, container: container)
        await checkAwaitedCountsAreDurable(targets: targets, container: container)
        await checkFailedCommitReportsFalse(targets: targets, outcomes: outcomes, container: container)
        await checkAppAdoptsHelperAfterRefusedSave(targets: targets, container: container)
        await checkRefusedButWrittenCommitIsAdopted(targets: targets, container: container)
        await checkPausePreservesUnclearedBlocker(targets: targets, container: container)
        try checkOutputFileContainsRules(container: container)

        print("PASS test_auto_update_rule_counts")
    }

    /// The app's refused save keeps its counts unsaved. Its own delayed notifications must not clear
    /// the flag, a run in progress owns the counts, and a later helper revision must be adopted, so the
    /// app stops holding its own numbers. The shared sync type is the production rule the app calls.
    private static func checkAppAdoptsHelperAfterRefusedSave(
        targets: [ContentBlockerTargetInfo], container: URL
    ) async {
        let dir = container.appendingPathComponent("refused-then-helper", isDirectory: true)
        let (idA, idB) = (targets[0].bundleIdentifier, targets[1].bundleIdentifier)
        let app = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        let helper = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        await app.loadData()
        await helper.loadData()

        var sync = ProtobufDataManager.AppliedRuleCountsSync()
        let seeded = await app.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 900, idB: 800], approachingIdentifiers: [], targets: targets
        )
        expect(seeded, "seed commit must reach disk")
        sync.matched(storeRevision: app.ruleCountsRevision)
        let seededRevision = app.ruleCountsRevision

        // The app's save is refused: the directory is read-only, so nothing reaches disk.
        setPermissions(0o500, of: dir)
        let refused = await app.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 1, idB: 2], approachingIdentifiers: [], targets: targets
        )
        setPermissions(0o700, of: dir)
        expect(!refused, "the app's save must be refused")
        sync.refused(storeRevision: app.ruleCountsRevision)
        expect(sync.isUnsaved, "a refused save must leave the counts unsaved")

        // A delayed notification from the app's own earlier commit arrives. Nothing foreign was written.
        _ = await app.refreshFromDiskIfModified()
        expect(!sync.shouldAdopt(storeRevision: app.ruleCountsRevision, runInProgress: false),
               "an own echo must not replace the unsaved counts")
        expect(sync.isUnsaved, "an own echo must not clear the unsaved flag")

        // The helper publishes a later revision. The app must adopt it, even though its save failed.
        await helper.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 1000, idB: 700], approachingIdentifiers: [], targets: targets
        )
        _ = await app.refreshFromDiskIfModified()
        expect(app.ruleCountsRevision == seededRevision + 1, "the helper's commit must take the next revision")
        expect(!sync.shouldAdopt(storeRevision: app.ruleCountsRevision, runInProgress: true),
               "a run in progress must keep its counts even for a foreign revision")
        expect(sync.shouldAdopt(storeRevision: app.ruleCountsRevision, runInProgress: false),
               "a foreign revision must be adopted once no run is in progress")
        expectEqual(app.ruleCountsByCategory[idA], Int32(1000), "the adopted store must hold the helper's split")
        sync.matched(storeRevision: app.ruleCountsRevision)
        expect(!sync.isUnsaved, "adopting the store must clear the unsaved flag")

        // A later successful save by the app also clears the flag.
        sync.refused(storeRevision: app.ruleCountsRevision)
        let retried = await app.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 5, idB: 6], approachingIdentifiers: [], targets: targets
        )
        expect(retried, "the retry must reach disk")
        sync.matched(storeRevision: app.ruleCountsRevision)
        expect(!sync.isUnsaved, "a successful retry must clear the unsaved flag")
    }

    /// A save can return false after its data file reached disk (the version write failed). The app
    /// records the refusal, reads the store back, and finds the counts it tried to write.
    private static func checkRefusedButWrittenCommitIsAdopted(
        targets: [ContentBlockerTargetInfo], container: URL
    ) async {
        let dir = container.appendingPathComponent("refused-but-written", isDirectory: true)
        let (idA, idB) = (targets[0].bundleIdentifier, targets[1].bundleIdentifier)
        let app = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        await app.loadData()
        await app.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 900, idB: 800], approachingIdentifiers: [], targets: targets
        )
        var sync = ProtobufDataManager.AppliedRuleCountsSync()
        sync.matched(storeRevision: app.ruleCountsRevision)

        // A directory where the version file belongs fails the version write after the data write.
        // The store's version name is the one ProtobufDataManager uses for its data file.
        let versionURL = dir.appendingPathComponent("wblock_data.version")
        try? FileManager.default.removeItem(at: versionURL)
        try? FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true)
        let refused = await app.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 5, idB: 6], approachingIdentifiers: [], targets: targets
        )
        expect(!refused, "a version write that fails must report the commit as not confirmed")
        sync.refused(storeRevision: app.ruleCountsRevision)

        let reader = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        await reader.loadData()
        expectEqual(reader.lastRuleCount, 11, "the refused save's data must be on disk")
        expect(!sync.shouldAdopt(storeRevision: app.ruleCountsRevision, runInProgress: false),
               "before the app reads the store back, its own refused save must hold")

        _ = await app.refreshFromDiskIfModified()
        expect(sync.shouldAdopt(storeRevision: app.ruleCountsRevision, runInProgress: false),
               "the written counts must be adopted after the read-back")
        expectEqual(app.ruleCountsByCategory[idA], Int32(5), "the read-back must show the written split")
        sync.matched(storeRevision: app.ruleCountsRevision)
        expect(!sync.isUnsaved, "a read-back of the written counts must clear the unsaved flag")

        try? FileManager.default.removeItem(at: versionURL)
        let retried = await app.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 7, idB: 8], approachingIdentifiers: [], targets: targets
        )
        expect(retried, "the retry must reach disk once the version path is writable")
        expectEqual(app.lastRuleCount, 15, "the retry's total must be stored")
    }

    /// A paused rebuild records zero only for blockers whose inert output was written and reloaded.
    /// A blocker that failed keeps its stored count and flag, so the store makes no zero claim for it.
    private static func checkPausePreservesUnclearedBlocker(
        targets: [ContentBlockerTargetInfo], container: URL
    ) async {
        let dir = container.appendingPathComponent("pause-partial", isDirectory: true)
        let (idA, idB) = (targets[0].bundleIdentifier, targets[1].bundleIdentifier)
        let store = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        await store.loadData()
        await store.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 900, idB: 800], approachingIdentifiers: [idB], targets: targets
        )

        let recorded = await SharedAutoUpdateManager.recordClearedRuleCounts(
            targets: targets, keepingStored: [idB], dataManager: store
        )
        expect(recorded, "the partial clear must still commit")
        expectEqual(store.ruleCountsByCategory[idA], Int32(0), "a cleared blocker must store zero")
        expectEqual(store.ruleCountsByCategory[idB], Int32(800), "an uncleared blocker must keep its stored count")
        expectEqual(store.lastRuleCount, 800, "the total must be the cleared zero plus the kept count")
        expectEqual(store.categoriesApproachingLimit, [idB], "an uncleared blocker must keep its stored flag")
    }

    private static func setPermissions(_ mode: Int, of dir: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: dir.path)
    }

    /// Two writers from separate managers commit the same total with different splits, and
    /// run concurrently. Each read-modify-write runs under the store's file lock, so each commit
    /// takes its own revision. Two commits sharing a revision would leave the final revision one
    /// short, and an open app would keep a stale split. The result holds for any schedule.
    private static func checkConcurrentWritersKeepRevisionsUnique(
        targets: [ContentBlockerTargetInfo], container: URL
    ) async throws {
        let dir = container.appendingPathComponent("concurrent", isDirectory: true)
        let (idA, idB) = (targets[0].bundleIdentifier, targets[1].bundleIdentifier)
        let seed = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        await seed.loadData()
        await seed.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 900, idB: 800], approachingIdentifiers: [], targets: targets
        )
        await seed.saveDataImmediately()
        let baseRevision = seed.ruleCountsRevision

        let reader = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        let writerOne = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        let writerTwo = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        await reader.loadData()
        await writerOne.loadData()
        await writerTwo.loadData()

        async let oneCommitted = writerOne.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 1000, idB: 700], approachingIdentifiers: [], targets: targets
        )
        async let twoCommitted = writerTwo.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 650, idB: 1050], approachingIdentifiers: [], targets: targets
        )
        let (oneSaved, twoSaved) = await (oneCommitted, twoCommitted)
        expect(oneSaved && twoSaved, "both concurrent commits must be confirmed")

        let fresh = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        await fresh.loadData()
        expectEqual(fresh.ruleCountsRevision, baseRevision + 2, "two committed count writes must take two revisions")
        let splits = (fresh.ruleCountsByCategory[idA], fresh.ruleCountsByCategory[idB])
        expect(splits == (Int32(1000), Int32(700)) || splits == (Int32(650), Int32(1050)),
               "the stored split must be one writer's whole split, not a mix (got \(String(describing: splits)))")
        expectEqual(fresh.lastRuleCount, 1700, "a same-total interleaving keeps the total")
        _ = await reader.refreshFromDiskIfModified()
        expectEqual(reader.ruleCountsRevision, fresh.ruleCountsRevision, "the reader must converge to the stored revision")
    }

    /// An awaited count update is on disk when it returns. A fresh reader must see it at
    /// once, not after the 500 ms save debounce.
    private static func checkAwaitedCountsAreDurable(
        targets: [ContentBlockerTargetInfo], container: URL
    ) async {
        let dir = container.appendingPathComponent("durable", isDirectory: true)
        let (idA, idB) = (targets[0].bundleIdentifier, targets[1].bundleIdentifier)
        let writer = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        await writer.loadData()
        await writer.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 1234, idB: 5], approachingIdentifiers: [], targets: targets
        )

        let fresh = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        await fresh.loadData()
        expectEqual(fresh.lastRuleCount, 1239, "an awaited count update must be on disk before it returns")
        expectEqual(fresh.ruleCountsByCategory[idA], Int32(1234), "the awaited per-blocker count must be on disk")
    }

    /// A commit the disk refuses reports `false` and leaves the stored counts as they were.
    /// The app keeps the run's counts in memory while the store holds the old ones, and the
    /// rebuild caller logs the refusal without failing a run Safari has already loaded.
    private static func checkFailedCommitReportsFalse(
        targets: [ContentBlockerTargetInfo],
        outcomes: [String: ContentBlockerService.ContentBlockerTargetOutcome],
        container: URL
    ) async {
        let dir = container.appendingPathComponent("failed-commit", isDirectory: true)
        let (idA, idB) = (targets[0].bundleIdentifier, targets[1].bundleIdentifier)
        let writer = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        await writer.loadData()
        await writer.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 300, idB: 200], approachingIdentifiers: [], targets: targets
        )
        let stored = writer.lastRuleCount

        let readOnly: [FileAttributeKey: Any] = [.posixPermissions: 0o500]
        try? FileManager.default.setAttributes(readOnly, ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }

        let saved = await writer.updateAppliedRuleCounts(
            countsByBundleIdentifier: [idA: 9, idB: 9], approachingIdentifiers: [], targets: targets
        )
        expect(!saved, "a commit that cannot reach disk must report false")

        let recorded = await SharedAutoUpdateManager.recordRebuiltRuleCounts(
            targets: targets, outcomes: outcomes, dataManager: writer
        )
        expect(!recorded, "a rebuild whose counts cannot be committed must report false")

        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let fresh = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dir)
        await fresh.loadData()
        expectEqual(fresh.lastRuleCount, stored, "a refused commit must leave the stored total as it was")
    }

    private static func filter(_ name: String, updated: TimeInterval) -> FilterList {
        FilterList(
            name: name,
            url: URL(string: "https://example.com/\(name).txt")!,
            category: .ads,
            isSelected: true,
            lastUpdated: Date(timeIntervalSince1970: updated)
        )
    }

    private static func write(_ content: String, for filter: FilterList, in container: URL) throws {
        let url = container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter))
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func compile(
        _ filters: [FilterList],
        target: ContentBlockerTargetInfo,
        groupIdentifier: String,
        container: URL
    ) throws -> ContentBlockerService.ContentBlockerTargetOutcome {
        let ordered = ContentBlockerMappingService.orderedForCompilation(filters)
        return try ContentBlockerService.compileTargetRules(
            filters: filters,
            orderedSelectedFilters: ordered,
            targetInfo: target,
            allTargets: [target],
            disabledSites: [],
            extraRulesText: nil,
            groupIdentifier: groupIdentifier,
            containerURL: container
        )
    }

    /// The reload storm came from a paused run reading whole 19 MB outputs to find the inert
    /// placeholder. The size check must call the placeholder empty and real output non-empty,
    /// and a file of the placeholder's size with other bytes must still count as rules.
    private static func checkOutputFileContainsRules(container: URL) throws {
        let inertBytes = Data(ContentBlockerService.inertContentBlockerRulesJSON.utf8)
        let inert = container.appendingPathComponent("inert-output.json")
        try inertBytes.write(to: inert)
        expect(!SharedAutoUpdateManager.outputFileContainsRules(at: inert),
               "the inert placeholder output must not count as rules")

        let sameSize = container.appendingPathComponent("same-size-output.json")
        try Data(repeating: UInt8(ascii: " "), count: inertBytes.count).write(to: sameSize)
        expect(SharedAutoUpdateManager.outputFileContainsRules(at: sameSize),
               "an output of the placeholder's size with other bytes must count as rules")

        let real = container.appendingPathComponent("real-output.json")
        try Data("[{\"trigger\":{\"url-filter\":\"a\"},\"action\":{\"type\":\"block\"}}]".utf8).write(to: real)
        expect(SharedAutoUpdateManager.outputFileContainsRules(at: real),
               "real rules output must count as rules")

        let missing = container.appendingPathComponent("missing-output.json")
        expect(!SharedAutoUpdateManager.outputFileContainsRules(at: missing),
               "a missing output holds no rules")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fail("\(message): actual=\(String(describing: actual)) expected=\(String(describing: expected))")
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
