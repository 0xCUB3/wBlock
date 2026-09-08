import Foundation
import wBlockCoreService

@main
@MainActor
struct ProtobufReliabilityTests {
    static func main() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-protobuf-reliability-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        await testDurableMigrationAndCorruptionRecovery(root: root.appendingPathComponent("recovery"))
        await testCorruptMainWithoutBackup(root: root.appendingPathComponent("no-backup-recovery"))
        await testMigrationFailureAndCanonicalPrecedence(root: root.appendingPathComponent("migration-failure"))
        await testThreeWayDeletionAndInsertion(root: root.appendingPathComponent("merge"))
        print("PASS")
    }

    private static func testCorruptMainWithoutBackup(root: URL) async {
        let standardSuite = "test.wblock.protobuf.no-backup.standard.\(UUID().uuidString)"
        let groupSuite = "test.wblock.protobuf.no-backup.group.\(UUID().uuidString)"
        let standard = UserDefaults(suiteName: standardSuite)!
        let group = UserDefaults(suiteName: groupSuite)!
        defer {
            standard.removePersistentDomain(forName: standardSuite)
            group.removePersistentDomain(forName: groupSuite)
        }

        let manager = await makeManager(root: root, standard: standard, group: group)
        await manager.loadData()
        let dataURL = root.appendingPathComponent("wblock_data.pb")
        let backupURL = root.appendingPathComponent("wblock_data_backup.pb")
        try! FileManager.default.removeItem(at: backupURL)
        let corruptBytes = Data([0xff, 0x01, 0xff])
        try! corruptBytes.write(to: dataURL, options: .atomic)

        await manager.loadData()
        let repairedBytes = try! Data(contentsOf: dataURL)
        expect(repairedBytes != corruptBytes, "no-backup corruption recovery must install a valid fallback canonical inside recovery")
        expect(FileManager.default.fileExists(atPath: backupURL.path), "fallback recovery must seed a new known-good backup")
        let restarted = await makeManager(root: root, standard: standard, group: group)
        await restarted.loadData()
        let restartedLevel = await restarted.selectedBlockingLevel
        expect(restartedLevel == "recommended", "fallback canonical must survive restart")
    }

    private static func testDurableMigrationAndCorruptionRecovery(root: URL) async {
        let standardSuite = "test.wblock.protobuf.standard.\(UUID().uuidString)"
        let groupSuite = "test.wblock.protobuf.group.\(UUID().uuidString)"
        let standard = UserDefaults(suiteName: standardSuite)!
        let group = UserDefaults(suiteName: groupSuite)!
        defer {
            standard.removePersistentDomain(forName: standardSuite)
            group.removePersistentDomain(forName: groupSuite)
        }
        standard.set(true, forKey: "hasCompletedOnboarding")
        standard.set("legacy-level", forKey: "selectedBlockingLevel")
        group.set(false, forKey: "autoUpdateEnabled")

        let manager = await makeManager(root: root, standard: standard, group: group)
        await manager.loadData()
        let migratedOnboarding = await manager.hasCompletedOnboarding
        let migratedLevel = await manager.selectedBlockingLevel
        let migratedAutoUpdate = await manager.autoUpdateEnabled
        expect(migratedOnboarding, "legacy onboarding state must survive first migration")
        expect(migratedLevel == "legacy-level", "legacy settings must be durably migrated before defaults")
        expect(!migratedAutoUpdate, "legacy auto-update setting must survive first migration")

        let dataURL = root.appendingPathComponent("wblock_data.pb")
        let backupURL = root.appendingPathComponent("wblock_data_backup.pb")
        let flagURL = root.appendingPathComponent("migration_completed.flag")
        expect(FileManager.default.fileExists(atPath: dataURL.path), "migration must persist main data")
        expect(FileManager.default.fileExists(atPath: backupURL.path), "first durable write must seed last-known-good backup")
        expect(FileManager.default.fileExists(atPath: flagURL.path), "migration flag must follow durable data")

        await manager.setSelectedBlockingLevel("newer-level")
        let savedNewer = await manager.saveDataImmediately()
        expect(savedNewer, "second state must persist")
        let corruptBytes = Data([0xff, 0x00, 0xff])
        let backupBytesBeforeUnreadableProbe = try! Data(contentsOf: backupURL)
        try! corruptBytes.write(to: dataURL, options: .atomic)

        // A transient backup read failure must not move/replace either original.
        try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: backupURL.path)
        await manager.loadData()
        let mainAfterUnreadableBackup = try! Data(contentsOf: dataURL)
        expect(mainAfterUnreadableBackup == corruptBytes, "unreadable backup must leave corrupt main in place for retry")
        try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        let backupAfterUnreadableProbe = try! Data(contentsOf: backupURL)
        expect(backupAfterUnreadableProbe == backupBytesBeforeUnreadableProbe, "transient backup read failure must not alter backup bytes")

        await manager.loadData()
        let recoveredLevel = await manager.selectedBlockingLevel
        expect(recoveredLevel == "legacy-level", "corrupt main must recover previous known-good backup")
        await manager.setSelectedBlockingLevel("after-recovery")
        let savedAfterRecovery = await manager.saveDataImmediately()
        expect(savedAfterRecovery, "recovered store must remain writable")

        let restarted = await makeManager(root: root, standard: standard, group: group)
        await restarted.loadData()
        let restartedLevel = await restarted.selectedBlockingLevel
        expect(restartedLevel == "after-recovery", "mutation after repair must survive restart")
    }

    private static func testMigrationFailureAndCanonicalPrecedence(root: URL) async {
        let standardSuite = "test.wblock.protobuf.failure.standard.\(UUID().uuidString)"
        let groupSuite = "test.wblock.protobuf.failure.group.\(UUID().uuidString)"
        let standard = UserDefaults(suiteName: standardSuite)!
        let group = UserDefaults(suiteName: groupSuite)!
        defer {
            standard.removePersistentDomain(forName: standardSuite)
            group.removePersistentDomain(forName: groupSuite)
        }

        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try! FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        let failing = await makeManager(root: root, standard: standard, group: group)
        await failing.loadData()
        let failedMain = root.appendingPathComponent("wblock_data.pb")
        let failedFlag = root.appendingPathComponent("migration_completed.flag")
        expect(!FileManager.default.fileExists(atPath: failedMain.path), "failed migration must not create defaults/main")
        expect(!FileManager.default.fileExists(atPath: failedFlag.path), "failed migration must not stamp completion flag")
        try! FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)

        standard.set("legacy-poison", forKey: "selectedBlockingLevel")
        let seed = await makeManager(root: root, standard: standard, group: group)
        await seed.loadData()
        await seed.setSelectedBlockingLevel("canonical")
        let canonicalSaved = await seed.saveDataImmediately()
        expect(canonicalSaved, "canonical seed must persist")
        try? FileManager.default.removeItem(at: failedFlag)

        standard.set("legacy-should-not-win", forKey: "selectedBlockingLevel")
        let canonicalReader = await makeManager(root: root, standard: standard, group: group)
        await canonicalReader.loadData()
        let canonicalLevel = await canonicalReader.selectedBlockingLevel
        expect(canonicalLevel == "canonical", "existing canonical store must win when migration flag is missing")
        expect(FileManager.default.fileExists(atPath: failedFlag.path), "valid canonical store should restamp missing migration flag")

        await testConcurrentInitialization(root: root.appendingPathComponent("concurrent-init"))
    }

    private static func testConcurrentInitialization(root: URL) async {
        let standardSuiteA = "test.wblock.protobuf.concurrent.standard.a.\(UUID().uuidString)"
        let standardSuiteB = "test.wblock.protobuf.concurrent.standard.b.\(UUID().uuidString)"
        let groupSuiteA = "test.wblock.protobuf.concurrent.group.a.\(UUID().uuidString)"
        let groupSuiteB = "test.wblock.protobuf.concurrent.group.b.\(UUID().uuidString)"
        let standardA = UserDefaults(suiteName: standardSuiteA)!
        let standardB = UserDefaults(suiteName: standardSuiteB)!
        let groupA = UserDefaults(suiteName: groupSuiteA)!
        let groupB = UserDefaults(suiteName: groupSuiteB)!
        defer {
            standardA.removePersistentDomain(forName: standardSuiteA)
            standardB.removePersistentDomain(forName: standardSuiteB)
            groupA.removePersistentDomain(forName: groupSuiteA)
            groupB.removePersistentDomain(forName: groupSuiteB)
        }
        standardA.set("candidate-a", forKey: "selectedBlockingLevel")
        standardB.set("candidate-b", forKey: "selectedBlockingLevel")

        let managerA = await makeManager(root: root, standard: standardA, group: groupA)
        let managerB = await makeManager(root: root, standard: standardB, group: groupB)
        async let loadA: Void = managerA.loadData()
        async let loadB: Void = managerB.loadData()
        _ = await (loadA, loadB)

        let finalA = await managerA.selectedBlockingLevel
        let finalB = await managerB.selectedBlockingLevel
        expect(finalA == finalB, "concurrent initializers must converge on one canonical store")
        expect(finalA == "candidate-a" || finalA == "candidate-b", "canonical store must be one complete migration candidate")
        expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("migration_completed.flag").path),
               "migration flag must be written only after coordinated canonical initialization")
    }

    private static func testThreeWayDeletionAndInsertion(root: URL) async {
        let standardSuite = "test.wblock.protobuf.merge.standard.\(UUID().uuidString)"
        let groupSuite = "test.wblock.protobuf.merge.group.\(UUID().uuidString)"
        let standard = UserDefaults(suiteName: standardSuite)!
        let group = UserDefaults(suiteName: groupSuite)!
        defer {
            standard.removePersistentDomain(forName: standardSuite)
            group.removePersistentDomain(forName: groupSuite)
        }

        let seed = await makeManager(root: root, standard: standard, group: group)
        await seed.loadData()
        let base = FilterList(
            name: "Base",
            url: URL(string: "https://example.com/base.txt")!,
            category: .ads,
            isSelected: true
        )
        await seed.updateFilterLists([base])

        let deleter = await makeManager(root: root, standard: standard, group: group)
        let staleWriter = await makeManager(root: root, standard: standard, group: group)
        await deleter.loadData()
        await staleWriter.loadData()
        await deleter.removeFilterList(withId: base.id)
        await MainActor.run { staleWriter.setUserScriptShowEnabledOnly(true) }
        let staleSave = await staleWriter.saveDataImmediately()
        expect(staleSave, "stale unrelated writer must save")

        let deletionVerifier = await makeManager(root: root, standard: standard, group: group)
        await deletionVerifier.loadData()
        let deletionResult = await deletionVerifier.getFilterLists()
        expect(deletionResult.isEmpty, "stale save must not resurrect externally deleted filter")

        await deletionVerifier.updateFilterLists([base])
        let inserter = await makeManager(root: root, standard: standard, group: group)
        let staleCollectionWriter = await makeManager(root: root, standard: standard, group: group)
        await inserter.loadData()
        await staleCollectionWriter.loadData()
        let inserted = FilterList(
            name: "Concurrent",
            url: URL(string: "https://example.com/concurrent.txt")!,
            category: .privacy
        )
        await inserter.updateFilterLists([base, inserted])
        await staleCollectionWriter.updateFilterLists([base])

        let insertionVerifier = await makeManager(root: root, standard: standard, group: group)
        await insertionVerifier.loadData()
        let insertionResult = await insertionVerifier.getFilterLists()
        let ids = Set(insertionResult.map(\.id))
        expect(ids == [base.id, inserted.id], "stale collection replacement must preserve concurrent insertion")
    }

    private static func makeManager(
        root: URL,
        standard: UserDefaults,
        group: UserDefaults
    ) async -> ProtobufDataManager {
        ProtobufDataManager.makeIsolatedForTesting(
            dataDirectoryURL: root,
            standardDefaults: standard,
            groupDefaults: group
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
