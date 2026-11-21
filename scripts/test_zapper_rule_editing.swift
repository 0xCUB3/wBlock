import Foundation
import wBlockCoreService

// Link against the signed Debug build's wBlockCoreService.framework.
@main
struct ZapperRuleEditingTests {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        func manager() -> ProtobufDataManager {
            ProtobufDataManager.makeIsolatedForTesting(
                dataDirectoryURL: directory
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

        _ = await app.refreshFromDiskIfModified(forceRead: true)
        await browser.setZapperRules(forHost: host, rules: browser.getZapperRules(forHost: host) + [".concurrent"])
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
            dataDirectoryURL: blockedPath
        )
        let failedEdit = await failing.replaceZapperRule(".old", with: ".new", forHost: host)
        precondition(!failedEdit, "Disk failures must not report a successful edit")
        let failedSync = await failing.synchronizeZapperRules(forHost: host, rules: [".new"])
        precondition(failedSync == nil, "Disk failures must not acknowledge a browser sync")

        // Kill switches on hosts without rules are listed, sync, and are dropped when re-enabled.
        let switched = manager()
        await switched.setZapperRulesDisabled(true, forHost: "switch-only.example")
        precondition(switched.getDisabledZapperDomains().contains("switch-only.example"),
                     "A disabled host with no rules must be listed as disabled")
        precondition(switched.getZapperDomains().contains("switch-only.example"),
                     "A disabled host with no rules must be listed as a host")
        await switched.applyZapperRulesBatch(rulesByHost: [:], disabledByHost: ["batch-only.example": true])
        precondition(switched.isZapperDisabled(forHost: "batch-only.example"),
                     "A batch kill switch must create an entry for a host without rules")
        await switched.setZapperRulesDisabled(false, forHost: "switch-only.example")
        precondition(!switched.getZapperDomains().contains("switch-only.example"),
                     "Re-enabling a host with no rules must drop its entry")
        await switched.applyZapperRulesBatch(rulesByHost: [:], disabledByHost: ["batch-only.example": false])
        precondition(!switched.getDisabledZapperDomains().contains("batch-only.example"),
                     "A batch enable must clear the kill switch")
        precondition(!switched.getZapperDomains().contains("batch-only.example"),
                     "A batch enable on a host with no rules must drop its entry")

        // A browser delta removes selectors as pending deletions and re-adds cancel them.
        let deltaHost = "delta.example"
        await app.setZapperRules(forHost: deltaHost, rules: [".a", ".b"])
        let afterDelta = await app.applyZapperRuleDelta(forHost: deltaHost, added: [".c", "  "], removed: [".a"])
        precondition(afterDelta == [".b", ".c"], "A delta must remove its selectors and add new ones")
        let deltaSync = await browser.synchronizeZapperRules(forHost: deltaHost, rules: [".a", ".b", ".c"])
        precondition(deltaSync == [".b", ".c"], "A removed selector must stay suppressed against a stale browser snapshot")
        let readded = await app.applyZapperRuleDelta(forHost: deltaHost, added: [".a"], removed: [])
        precondition(readded == [".b", ".c", ".a"], "Re-adding a selector must cancel its pending deletion")
        let emptied = await app.applyZapperRuleDelta(forHost: deltaHost, added: [], removed: [".b", ".c", ".a"])
        precondition(emptied == [], "A delta that removes everything must leave no selectors")
        _ = await browser.synchronizeZapperRules(forHost: deltaHost, rules: [])
        precondition(!browser.getZapperDomains().contains(deltaHost),
                     "A host with no rules and no pending deletions must be dropped")
        print("PASS zapper replacement, validation, ordering, disabled state, disk persistence, stale editors, browser reconciliation, and write failures")
    }
}
