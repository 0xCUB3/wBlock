import Foundation
@testable import wBlockCoreService

// A page's cached userscript copy carries the payload revision of the native
// host that served it. A restarted host must arrive at the same revision for
// the same scripts, and a changed script must change it.
@main
@MainActor
struct UserScriptPayloadRevisionRegression {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wblock-revision-\(UUID())")
        let scripts = root.appendingPathComponent("userscripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        UserScriptManager.scriptsDirectoryOverrideForTesting = scripts
        // Built-in scripts would otherwise download after launch and change the
        // revision at an arbitrary point, which made this test flaky in CI.
        UserScriptManager.skipsStartupDownloadsForTesting = true

        var script = UserScript(
            name: "Revision Probe",
            content: "// ==UserScript==\n// @name Revision Probe\n// @match *://*/*\n// ==/UserScript==\nvoid 0;"
        )
        script.parseMetadata()
        script.isLocal = true
        script.isEnabled = true
        let store = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: root)
        await store.loadData()
        _ = await store.replaceUserScripts([script])
        try script.content.write(
            to: scripts.appendingPathComponent("\(script.id.uuidString).user.js"), atomically: true, encoding: .utf8)

        // The first host lives through changes that end where they started.
        let first = UserScriptManager.makeIsolatedForTesting(dataManager: store)
        await first.waitUntilReady()
        await first.setUserScript(script, isEnabled: false)
        await first.setUserScript(script, isEnabled: true)
        await first.refreshFromDiskForExecution()

        // A restarted host reads the same store from disk.
        let restartedStore = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: root)
        await restartedStore.loadData()
        let restarted = UserScriptManager.makeIsolatedForTesting(dataManager: restartedStore)
        await restarted.waitUntilReady()
        await restarted.refreshFromDiskForExecution()
        precondition(restarted.userScript(withId: script.id)?.isEnabled == true, "restarted host loaded the script")
        precondition(first.payloadMutationRevision == restarted.payloadMutationRevision,
                     "a restarted host keeps the revision of unchanged scripts")
        precondition(first.payloadMutationRevision < 1 << 53, "the revision is a safe integer for the injector")

        let unchanged = restarted.payloadMutationRevision
        await first.setUserScript(script, isEnabled: false)
        await restarted.refreshFromDiskForExecution()
        precondition(restarted.userScript(withId: script.id)?.isEnabled == false, "restarted host saw the toggle")
        precondition(restarted.payloadMutationRevision != unchanged, "disabling a script changes the revision")
        await first.setUserScript(script, isEnabled: true)
        await restarted.refreshFromDiskForExecution()
        precondition(restarted.payloadMutationRevision == unchanged, "the revision follows the state, not its history")

        _ = await first.saveEditedContent(for: script.id, newContent: script.content + "\nvoid 1;")
        await restarted.refreshFromDiskForExecution()
        precondition(restarted.userScript(withId: script.id)?.content.hasSuffix("void 1;") == true,
                     "restarted host saw the edit")
        precondition(restarted.payloadMutationRevision != unchanged, "changed content changes the revision")
        print("PASS: userscript payload revision is stable across hosts and follows script changes")
    }
}
