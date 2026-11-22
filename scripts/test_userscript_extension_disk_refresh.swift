import Foundation
@testable import wBlockCoreService

/// An extension process that outlives app-side userscript changes must refresh
/// from disk before serving scripts, writing per-site toggles, or checking
/// auto-update eligibility.
@main
@MainActor
struct UserScriptExtensionDiskRefreshTests {
    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fail(message)
        }
    }

    private static func send(_ message: [String: Any]) async -> [String: Any] {
        await withCheckedContinuation { continuation in
            WebExtensionRequestHandler.respond(to: message) { reply in
                continuation.resume(returning: reply as? [String: Any] ?? [:])
            }
        }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-ext-disk-refresh-\(UUID().uuidString)", isDirectory: true)
        let scripts = root.appendingPathComponent("userscripts", isDirectory: true)
        let data = root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        defer {
            WebExtensionRequestHandler.userScriptManagerOverrideForTesting = nil
            UserScriptManager.scriptsDirectoryOverrideForTesting = nil
            UserScriptManager.skipsStartupDownloadsForTesting = false
            try? FileManager.default.removeItem(at: root)
        }

        UserScriptManager.scriptsDirectoryOverrideForTesting = scripts
        UserScriptManager.skipsStartupDownloadsForTesting = true

        let initialSourceA = """
        // ==UserScript==
        // @name Local Refresh Probe A
        // @match *://*/*
        // ==/UserScript==
        window.__scriptA = 'v1';
        """
        var scriptA = UserScript(name: "Local Refresh Probe A", content: initialSourceA)
        scriptA.parseMetadata()
        scriptA.isLocal = true
        scriptA.isEnabled = false

        let appData = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: data)
        await appData.loadData()
        _ = await appData.replaceUserScripts([scriptA])
        try initialSourceA.write(
            to: scripts.appendingPathComponent("\(scriptA.id.uuidString).user.js"),
            atomically: true,
            encoding: .utf8
        )
        let app = UserScriptManager.makeIsolatedForTesting(dataManager: appData)
        await app.waitUntilReady()

        let extData = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: data)
        await extData.loadData()
        let ext = UserScriptManager.makeIsolatedForTesting(dataManager: extData)
        await ext.waitUntilReady()

        WebExtensionRequestHandler.userScriptManagerOverrideForTesting = ext

        // Mark scripts fresh so maybeUpdateUserScripts stays off the network.
        let now = Int64(Date().timeIntervalSince1970)
        await appData.setScriptLastChecked(Dictionary(
            uniqueKeysWithValues: app.userScripts.map { ($0.id.uuidString, now) }
        ))
        _ = await appData.saveDataImmediately()

        // Mutate state strictly in the app manager while ext stays running in memory.
        await app.setUserScript(scriptA, isEnabled: true)
        let updatedSourceA = """
        // ==UserScript==
        // @name Local Refresh Probe A
        // @match *://*/*
        // ==/UserScript==
        window.__scriptA = 'v2';
        """
        let editError = await app.saveEditedContent(for: scriptA.id, newContent: updatedSourceA)
        expect(editError == nil, "editing script A in app should succeed, got: \(editError ?? "")")

        let sourceB = """
        // ==UserScript==
        // @name Local Refresh Probe B
        // @match *://example.com/*
        // ==/UserScript==
        window.__scriptB = true;
        """
        let addError = await app.addUserScript(fromSourceContent: sourceB)
        expect(addError == nil, "adding script B in app should succeed, got: \(addError?.localizedDescription ?? "")")
        guard let scriptB = app.userScripts.first(where: { $0.name == "Local Refresh Probe B" }) else {
            fail("app should contain newly added script B")
        }

        let appDisableOK = await app.setUserScript(withId: scriptA.id, disabledOnHost: "other.example", disabled: true)
        expect(appDisableOK, "disabling script A on other.example in app should succeed")

        // 1. getUserScripts must refresh from disk and serve app-enabled/edited/added scripts & host exclusions.
        let scriptsResponse = await send([
            "action": "getUserScripts",
            "url": "https://example.com/",
            "isTopFrame": true,
            "includeContent": true
        ])
        let descriptors = scriptsResponse["userScripts"] as? [[String: Any]] ?? []
        let byID = Dictionary(uniqueKeysWithValues: descriptors.compactMap { item -> (String, [String: Any])? in
            guard let id = item["id"] as? String else { return nil }
            return (id, item)
        })

        guard let descA = byID[scriptA.id.uuidString] else {
            fail("getUserScripts did not return script A enabled by app")
        }
        let contentA = descA["content"] as? String ?? ""
        expect(contentA.contains("window.__scriptA = 'v2'"), "getUserScripts must return updated content for script A")
        let disabledA = descA["disabledHosts"] as? [String] ?? []
        expect(disabledA.contains("other.example"), "getUserScripts must include app-saved disabledHosts for script A")
        expect(byID[scriptB.id.uuidString] != nil, "getUserScripts must return newly added script B")

        let excludedResponse = await send([
            "action": "getUserScripts",
            "url": "https://other.example/",
            "isTopFrame": true
        ])
        let excludedIDs = Set((excludedResponse["userScripts"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String })
        expect(!excludedIDs.contains(scriptA.id.uuidString), "getUserScripts must omit script A on excluded other.example")

        // 2. setUserScriptSiteDisabledState must find newly added script B and preserve app's other.example exclusion on A.
        let disableBReply = await send([
            "action": "setUserScriptSiteDisabledState",
            "scriptId": scriptB.id.uuidString,
            "host": "example.com",
            "disabled": true
        ])
        expect(disableBReply["ok"] as? Bool == true, "setUserScriptSiteDisabledState must find newly added script B")

        let disableAReply = await send([
            "action": "setUserScriptSiteDisabledState",
            "scriptId": scriptA.id.uuidString,
            "host": "example.com",
            "disabled": true
        ])
        expect(disableAReply["ok"] as? Bool == true, "setUserScriptSiteDisabledState for script A should succeed")

        _ = await appData.refreshFromDiskIfModified(forceRead: true)
        let mergedDisabledA = Set(appData.getUserScriptDisabledHosts(forScriptID: scriptA.id.uuidString))
        expect(
            mergedDisabledA == Set(["example.com", "other.example"]),
            "extension write must preserve app's other.example exclusion, got \(mergedDisabledA)"
        )

        // 3. maybeUpdateUserScripts must read autoUpdateEnabled and script updates from disk.
        await appData.setAutoUpdateEnabled(false)
        _ = await appData.saveDataImmediately()
        let pausedUpdateReply = await send(["action": "maybeUpdateUserScripts"])
        expect(
            pausedUpdateReply["skipped"] as? String == "disabled",
            "maybeUpdateUserScripts must honor autoUpdateEnabled = false from app, got \(pausedUpdateReply)"
        )

        // Re-enable autoUpdateEnabled while also adding script C on disk, and verify extension refreshes.
        await appData.setAutoUpdateEnabled(true)
        _ = await appData.saveDataImmediately()
        let sourceC = """
        // ==UserScript==
        // @name Local Refresh Probe C
        // @match *://example.com/*
        // ==/UserScript==
        window.__scriptC = true;
        """
        let addCError = await app.addUserScript(fromSourceContent: sourceC)
        expect(addCError == nil, "adding script C in app should succeed")
        guard let scriptC = app.userScripts.first(where: { $0.name == "Local Refresh Probe C" }) else {
            fail("app should contain newly added script C")
        }

        let enabledUpdateReply = await send(["action": "maybeUpdateUserScripts"])
        expect(
            enabledUpdateReply["ok"] as? Bool == true && enabledUpdateReply["skipped"] == nil,
            "maybeUpdateUserScripts must run when autoUpdateEnabled is re-enabled, got \(enabledUpdateReply)"
        )
        expect(
            ext.userScript(withId: scriptC.id) != nil,
            "maybeUpdateUserScripts must refresh ext manager from disk"
        )

        print("PASS: WebExtensionRequestHandler userscript handlers refresh app changes from disk")
    }
}
