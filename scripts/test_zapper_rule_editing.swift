import Foundation
import wBlockCoreService

// Link against the signed Debug build's wBlockCoreService.framework.
@main
struct ZapperRuleEditingTests {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "wblock-zapper-edit-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        func manager() -> ProtobufDataManager {
            ProtobufDataManager.makeIsolatedForTesting(
                dataDirectoryURL: directory, standardDefaults: defaults, groupDefaults: defaults
            )
        }
        let app = manager()
        let host = "example.com"
        await app.setZapperRules(forHost: host, rules: [".first", ".old", ".last"])
        await app.setZapperRulesDisabled(true, forHost: host)
        await app.setZapperRules(forHost: "other.example", rules: [".unrelated"])
        let browser = manager()
        _ = await browser.refreshFromDiskIfModified(forceRead: true)

        let edited = await app.replaceZapperRule(".old", with: "  main > .ad:not(.allowed)\n", forHost: host)
        precondition(edited)
        let expected = [".first", "main > .ad:not(.allowed)", ".last"]
        precondition(app.getZapperRules(forHost: host) == expected)
        let diskReader = manager()
        _ = await diskReader.refreshFromDiskIfModified(forceRead: true)
        precondition(diskReader.getZapperRules(forHost: host) == expected)
        precondition(diskReader.isZapperDisabled(forHost: host))
        precondition(app.isZapperDisabled(forHost: host))
        precondition(app.getZapperRules(forHost: "other.example") == [".unrelated"])

        for replacement in ["", " \n ", ".first", "main > .ad:not(.allowed)"] {
            let saved = await app.replaceZapperRule(expected[1], with: replacement, forHost: host)
            precondition(!saved, "Blank, duplicate, and unchanged edits must not save")
            precondition(app.getZapperRules(forHost: host) == expected)
        }
        let missing = await app.replaceZapperRule(".missing", with: expected[1], forHost: host)
        precondition(!missing, "An existing replacement must not make a missing original look saved")
        let stale = await browser.replaceZapperRule(".old", with: ".stale", forHost: host)
        precondition(!stale, "The original must still exist in the latest disk snapshot")
        let synced = await browser.synchronizeZapperRules(forHost: host, rules: [".first", ".old", ".last", ".new-browser-rule"])
        precondition(synced == expected + [".new-browser-rule"], "Stale sync must retain the edit and suppress the old selector")
        precondition(browser.isZapperDisabled(forHost: host))
        let consumed = await browser.consumeZapperPendingDeletions(forHost: host)
        precondition(consumed.isEmpty, "Successful sync acknowledges pending deletions")

        _ = await app.refreshFromDiskIfModified(forceRead: true)
        await browser.addZapperRule(".concurrent", forHost: host)
        let secondEdit = await app.replaceZapperRule(expected[1], with: ".edited-again", forHost: host)
        precondition(secondEdit)
        precondition(app.getZapperRules(forHost: host).contains(".concurrent"))
        let restored = await app.replaceZapperRule(".edited-again", with: expected[1], forHost: host)
        precondition(restored)
        let restoredSync = await browser.synchronizeZapperRules(forHost: host, rules: [".edited-again"])
        precondition(restoredSync?.contains(expected[1]) == true, "Editing back must clear the replacement's tombstone")
        precondition(restoredSync?.contains(".edited-again") == false)

        await app.deleteZapperRule(expected[1], forHost: host)
        let deletedEdit = await browser.replaceZapperRule(expected[1], with: ".resurrected", forHost: host)
        precondition(!deletedEdit, "Editing a deleted rule must not recreate it")
        _ = await browser.synchronizeZapperRules(forHost: host, rules: [])
        let cleared = await browser.synchronizeZapperRules(forHost: host, rules: [])
        precondition(cleared == [], "Browser clear must work after native changes are acknowledged")

        let reloaded = manager()
        _ = await reloaded.refreshFromDiskIfModified(forceRead: true)
        precondition(reloaded.getZapperRules(forHost: host).isEmpty)
        precondition(reloaded.getZapperRules(forHost: "other.example") == [".unrelated"])
        let blockedPath = directory.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blockedPath)
        let failing = ProtobufDataManager.makeIsolatedForTesting(
            dataDirectoryURL: blockedPath, standardDefaults: defaults, groupDefaults: defaults
        )
        let failedEdit = await failing.replaceZapperRule(".old", with: ".new", forHost: host)
        precondition(!failedEdit, "Disk failures must not report a successful edit")
        let failedSync = await failing.synchronizeZapperRules(forHost: host, rules: [".new"])
        precondition(failedSync == nil, "Disk failures must not acknowledge a browser sync")
        print("PASS zapper replacement, validation, ordering, disabled state, disk persistence, stale editors, browser reconciliation, and write failures")
    }
}
