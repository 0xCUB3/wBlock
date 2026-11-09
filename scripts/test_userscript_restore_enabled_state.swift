import Foundation
@testable import wBlockCoreService

// A script turned on earlier in the session must not be switched back on by the
// next disk sync after a backup restore lists it as off.
@main
@MainActor
struct UserScriptRestoreEnabledStateRegression {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wblock-restore-\(UUID())")
        let scripts = root.appendingPathComponent("userscripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        UserScriptManager.scriptsDirectoryOverrideForTesting = scripts

        func localScript(_ name: String) -> UserScript {
            var script = UserScript(
                name: name,
                content: "// ==UserScript==\n// @name \(name)\n// @match *://*/*\n// ==/UserScript==\nvoid 0;"
            )
            script.parseMetadata()
            script.isLocal = true
            script.isEnabled = false
            return script
        }
        let script = localScript("Restore Probe")
        let store = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: root)
        await store.loadData()
        _ = await store.replaceUserScripts([script])
        try script.content.write(
            to: scripts.appendingPathComponent("\(script.id.uuidString).user.js"), atomically: true, encoding: .utf8)

        let manager = UserScriptManager.makeIsolatedForTesting(dataManager: store)
        await manager.waitUntilReady()
        await manager.setUserScript(script, isEnabled: true)
        precondition(manager.userScript(withId: script.id)?.isEnabled == true, "enable before restore")

        await manager.restoreUserScriptsFromBackup([script])

        // Any later store write makes the manager sync from disk.
        await store.updateUserScript(localScript("Sync Trigger"))
        for _ in 0..<100 where manager.userScripts.count != store.getUserScripts().count {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        precondition(manager.userScripts.count == store.getUserScripts().count, "manager synced from disk")
        precondition(store.getUserScripts().first { $0.id == script.id }?.isEnabled == false, "restore persisted Off")
        precondition(manager.userScript(withId: script.id)?.isEnabled == false, "sync kept the restored Off state")
        print("PASS: restore keeps the backup's enabled state after a disk sync")
    }
}
