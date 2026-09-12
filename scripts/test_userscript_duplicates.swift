import Foundation
import SwiftProtobuf
@testable import wBlockCoreService

@main
@MainActor
struct UserScriptDuplicateTests {
    static func main() async throws {
        func script(_ version: String, enabled: Bool = true, url: String? = nil) -> UserScript {
            var value = UserScript(name: "Videos default at 2x speed", url: url.flatMap(URL.init(string:)), content: "source")
            value.version = version
            value.isEnabled = enabled
            value.isLocal = url == nil
            return value
        }
        let a = script("1")
        let b = script("2")
        let c = script("3")
        for scripts in [[a, b, c], [a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a]] {
            let pairs = UserScriptDuplicateResolver.removalPairs(in: scripts)
            expect(pairs.count == 2, "three copies mean two removals, not three pairs")
            expect(Set(pairs.map(\.older.id)) == [a.id, b.id], "keep newest regardless of array order")
            expect(pairs.allSatisfy { $0.newer.id == c.id }, "every removal must point to the actual survivor")
        }
        expect(UserScriptDuplicateResolver.removalPairs(in: [a, a, a]).isEmpty,
               "never delete the shared source file for repeated UUIDs")
        let off = script("3", enabled: false)
        let equal = UserScriptDuplicateResolver.removalPairs(in: [off, c])
        expect(equal.first?.newer.id == c.id, "prefer enabled copy at equal version")
        let protected = UserScriptDuplicateResolver.removalPairs(in: [a, c], protectedIDs: [a.id])
        expect(protected.first?.newer.id == a.id, "retain built-in identity")
        let remoteA = script("1", url: "https://example.com/a.user.js")
        let remoteB = script("3", url: "https://example.com/a.user.js")
        let remoteC = script("2", url: "https://example.com/c.user.js")
        let mixed = UserScriptDuplicateResolver.removalPairs(in: [remoteA, remoteB, remoteC])
        expect(mixed.count == 2 && mixed.allSatisfy { $0.newer.id == remoteB.id },
               "mixed URL/name matches must not create a cycle that deletes every copy")
        var unrelated = script("1")
        unrelated.name = "Another script"
        expect(UserScriptDuplicateResolver.removalPairs(in: [a, unrelated]).isEmpty, "keep unrelated imports")

        var stable = a
        stable.localImportIdentity = "file:kept"
        expect(!CloudSyncLocalUserScriptReconciler.shouldRecordDeletion(
            name: a.name, identity: "file:kept", survivingScripts: [stable]
        ), "shared sync identity must not be tombstoned")
        expect(CloudSyncLocalUserScriptReconciler.shouldRecordDeletion(
            name: a.name, identity: "file:removed", survivingScripts: [stable]
        ), "distinct removed file needs its own tombstone")
        expect(!CloudSyncLocalUserScriptReconciler.shouldRecordDeletion(
            name: "  " + a.name.uppercased(), identity: nil, survivingScripts: [a]
        ), "legacy duplicate name must retain its sync identity")
        expect(CloudSyncLocalUserScriptReconciler.shouldRecordDeletion(
            name: a.name, identity: nil, survivingScripts: []
        ), "removing the last legacy copy still emits a tombstone")
        try await testPersistence(scripts: [a, b, c, unrelated])
        print("PASS: duplicate survivor planning, sync identity, exact deletion, and reload")
    }

    static func testPersistence(scripts: [UserScript]) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wblock-duplicates-\(UUID())")
        let suite = "test.wblock.duplicates.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        func manager() -> ProtobufDataManager {
            ProtobufDataManager.makeIsolatedForTesting(
                dataDirectoryURL: root, standardDefaults: defaults, groupDefaults: defaults
            )
        }
        let store = manager()
        await store.loadData()
        let saved = await store.replaceUserScripts(Array(scripts.prefix(3)))
        expect(saved, "seed store")
        await store.setAllUserScriptDisabledHosts([
            scripts[0].id.uuidString: ["removed.example"],
            scripts[2].id.uuidString: ["kept.example"]
        ])
        let staleWriter = manager()
        await staleWriter.loadData()
        let concurrent = manager()
        await concurrent.loadData()
        await concurrent.updateUserScript(scripts[3])
        let removed = await store.removeDuplicateUserScripts(withIDs: [scripts[0].id, scripts[1].id])
        expect(removed, "persist confirmed deletion")
        await staleWriter.updateUserScripts(Array(scripts.prefix(3)))
        let restarted = manager()
        await restarted.loadData()
        expect(Set(restarted.getUserScripts().map(\.id)) == [scripts[2].id, scripts[3].id],
               "cleanup preserves concurrent insert and stale upsert cannot resurrect removed IDs")
        expect(restarted.getUserScriptDisabledHosts() == [scripts[2].id.uuidString: ["kept.example"]],
               "preserve survivor's site state and remove deleted IDs' state")
        let repeated = await restarted.replaceUserScripts([scripts[2], scripts[2], scripts[2]])
        expect(repeated && restarted.getUserScripts().count == 1, "replacement repairs repeated UUIDs")

        // Bypass all writers to reproduce an already-corrupt installation.
        let file = root.appendingPathComponent("wblock_data.pb")
        var raw = try Wblock_Data_AppData(serializedBytes: Data(contentsOf: file))
        var copy = raw.userScripts[0]
        copy.id = copy.id.lowercased()
        raw.userScripts.append(copy)
        raw.userScripts.append(raw.userScripts[0])
        try raw.serializedData().write(to: file, options: .atomic)
        let repairedStore = manager()
        await repairedStore.loadData()
        expect(repairedStore.getUserScripts().map(\.id) == [scripts[2].id],
               "decode repairs repeated UUIDs, including differently cased IDs")
        let repairedRaw = try Wblock_Data_AppData(serializedBytes: Data(contentsOf: file))
        expect(repairedRaw.userScripts.count == 1, "repair must reach disk, not only hide UI rows")
        expect(repairedStore.getUserScriptDisabledHosts() == [scripts[2].id.uuidString: ["kept.example"]],
               "identity repair must preserve site preferences")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
