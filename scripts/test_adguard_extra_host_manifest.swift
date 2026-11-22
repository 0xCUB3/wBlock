import Foundation
import wBlockCoreService

@main
struct AdGuardExtraHostManifestTests {
    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-ag-extra-manifest-\(UUID().uuidString)", isDirectory: true)
        let scriptsDir = root.appendingPathComponent("userscripts", isDirectory: true)
        let dataDir = root.appendingPathComponent("data", isDirectory: true)
        let remoteDir = root.appendingPathComponent("remote", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
        defer {
            UserScriptManager.scriptsDirectoryOverrideForTesting = nil
            UserScriptManager.adGuardExtraHostManifestURLOverrideForTesting = nil
            UserScriptManager.skipsStartupDownloadsForTesting = false
            try? FileManager.default.removeItem(at: root)
        }

        UserScriptManager.scriptsDirectoryOverrideForTesting = scriptsDir
        UserScriptManager.skipsStartupDownloadsForTesting = true

        let manifestJSON = """
        {
          "schemaVersion": 1,
          "sourceURL": "https://userscripts.adtidy.org/release/adguard-extra/1.0/adguard-extra.user.js",
          "version": "1.1.41",
          "scriptSha256": "28ed470a8031b04dc058092f05b5c0dd038b23e2240ac17214c1b00dfd9b69e7",
          "hosts": [
            "facebook.com",
            "*.kinopoisk.ru",
            "*.bbc.co.uk",
            "*.sub.example.org",
            "twitch.tv",
            "overlap.example"
          ],
          "tinyShieldDomains": [
            "1000logos.net",
            "overlap.example"
          ]
        }
        """

        // 1. Manifest decoder and matching rules
        let manifestData = Data(manifestJSON.utf8)
        guard let manifest = AdGuardExtraHostManifest.decode(data: manifestData) else {
            fatalError("expected valid manifest to decode")
        }
        expect(manifest.matchesVersion("1.1.41"), "exact version should match")
        expect(!manifest.matchesVersion("1.1.42"), "mismatched version must fail")
        expect(manifest.matchesExtraHost("facebook.com"), "exact extra host")
        expect(manifest.matchesExtraHost("www.facebook.com"), "www-stripped extra host")
        expect(manifest.matchesExtraHost("WWW.Facebook.COM."), "case-insensitive trailing-dot host")
        expect(!manifest.matchesExtraHost("sub.facebook.com"), "non-wildcard subdomain must not match")
        expect(manifest.matchesExtraHost("hd.kinopoisk.ru"), "wildcard root subdomain")
        expect(manifest.matchesExtraHost("a.b.kinopoisk.ru"), "nested wildcard root subdomain")
        expect(manifest.matchesExtraHost("news.bbc.co.uk"), "3-label wildcard subdomain")
        expect(manifest.matchesExtraHost("a.b.bbc.co.uk"), "nested 3-label wildcard subdomain")
        expect(manifest.matchesExtraHost("bbc.co.uk"), "3-label wildcard root")
        expect(manifest.matchesExtraHost("www.bbc.co.uk"), "www-stripped 3-label wildcard root")
        expect(!manifest.matchesExtraHost("evilbbc.co.uk"), "suffix boundary must not match 3-label wildcard")
        expect(!manifest.matchesExtraHost("other.co.uk"), "sibling under public suffix must not match 3-label wildcard")
        expect(manifest.matchesExtraHost("x.sub.example.org"), "subdomain of 3-label wildcard")
        expect(manifest.matchesExtraHost("sub.example.org"), "exact 3-label wildcard root")
        expect(!manifest.matchesExtraHost("other.example.org"), "sibling subdomain must not match *.sub.example.org")
        expect(!manifest.matchesExtraHost("example.org"), "parent domain must not match *.sub.example.org")
        expect(manifest.matchesTinyShieldHost("1000logos.net"), "exact tinyShield host")
        expect(manifest.matchesTinyShieldHost("sub.1000logos.net"), "subdomain tinyShield host")
        expect(!manifest.matchesTinyShieldHost("apple.com"), "unrelated host must not match")

        // 2. End-to-end UserScriptManager gating, fallback, and duplicate tinyShield suppression
        let dataManager = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: dataDir)
        await dataManager.loadData()
        let manager = UserScriptManager.makeIsolatedForTesting(dataManager: dataManager)
        await manager.waitUntilReady()

        guard let adGuardExtra = manager.userScripts.first(where: { $0.name == "AdGuard Extra" }),
              let tinyShield = manager.userScripts.first(where: { $0.name == "tinyShield" }),
              let vaft = manager.userScripts.first(where: { $0.name == "TwitchAdSolutions (vaft)" })
        else { fatalError("expected built-in AdGuard Extra, tinyShield, and VAFT records") }

        func writeScript(_ script: UserScript, source: String) throws {
            let file = scriptsDir.appendingPathComponent("\(script.id.uuidString).user.js")
            try source.write(to: file, atomically: true, encoding: .utf8)
        }

        try writeScript(adGuardExtra, source: """
        // ==UserScript==
        // @name AdGuard Extra
        // @version 1.1.41
        // @match *://*/*
        // ==/UserScript==
        void 0;
        """)
        try writeScript(tinyShield, source: """
        // ==UserScript==
        // @name tinyShield
        // @version 4.1.0
        // @match *://1000logos.net/*
        // @match *://*.1000logos.net/*
        // @match *://overlap.example/*
        // @match *://*.overlap.example/*
        // ==/UserScript==
        void 0;
        """)
        try writeScript(vaft, source: """
        // ==UserScript==
        // @name TwitchAdSolutions (vaft)
        // @version 1.0.0
        // @match *://twitch.tv/*
        // @match *://*.twitch.tv/*
        // ==/UserScript==
        void 0;
        """)

        // Ensure tinyShield and AdGuard Extra are both enabled and hydrated from disk
        await manager.setUserScript(tinyShield, isEnabled: false)
        await manager.setUserScript(tinyShield, isEnabled: true)
        await manager.setUserScript(adGuardExtra, isEnabled: true)
        await manager.refreshFromDiskForExecution()

        func names(for url: String) -> Set<String> {
            Set(manager.getEnabledUserScriptsForURL(url).map(\.name))
        }
        func pageNames(for url: String) -> Set<String> {
            Set(manager.pageUserScripts(for: url).map { $0.script.name })
        }

        // Without cached manifest: falls back to *://*/*
        expect(names(for: "https://apple.com/").contains("AdGuard Extra"), "missing manifest falls back to *://*/*")
        let revBeforeManifest = manager.payloadMutationRevision

        // Fetch manifest via local file URL override and confirm payloadMutationRevision changes
        let remoteManifestFile = remoteDir.appendingPathComponent("adguard-extra-hosts.json")
        try manifestData.write(to: remoteManifestFile, options: .atomic)
        UserScriptManager.adGuardExtraHostManifestURLOverrideForTesting = remoteManifestFile

        let refreshed = await manager.refreshAdGuardExtraHostManifestIfNeeded()
        expect(refreshed, "refreshAdGuardExtraHostManifestIfNeeded should cache the manifest")
        let revAfterManifest = manager.payloadMutationRevision
        expect(revAfterManifest != revBeforeManifest, "manifest activation must advance payloadMutationRevision")

        // Second refresh with matching version should be a no-op
        let refreshedAgain = await manager.refreshAdGuardExtraHostManifestIfNeeded()
        expect(!refreshedAgain, "matching cached manifest should skip redundant fetch")

        // Standalone tinyShield ON: AdGuard Extra runs only on its `hosts`, skipped elsewhere
        expect(!names(for: "https://apple.com/").contains("AdGuard Extra"), "unrelated host skips AdGuard Extra")
        expect(!pageNames(for: "https://apple.com/").contains("AdGuard Extra"), "popup hides skipped AdGuard Extra")
        expect(names(for: "https://www.facebook.com/").contains("AdGuard Extra"), "www extra host runs AdGuard Extra")
        expect(names(for: "https://hd.kinopoisk.ru/film/1").contains("AdGuard Extra"), "wildcard extra host runs AdGuard Extra")
        expect(names(for: "https://1000logos.net/") == ["tinyShield"], "tinyShield-only host runs standalone tinyShield without AdGuard Extra")

        // Overlap host: AdGuard Extra runs (carrying bundled tinyShield) and standalone tinyShield is suppressed
        expect(names(for: "https://overlap.example/") == ["AdGuard Extra"], "overlap host suppresses duplicate standalone tinyShield")

        // Disabling AdGuard Extra on the overlap host restores standalone tinyShield
        _ = await manager.setUserScript(withId: adGuardExtra.id, disabledOnHost: "overlap.example", disabled: true)
        expect(names(for: "https://overlap.example/") == ["tinyShield"], "disabling AdGuard Extra on overlap host lets standalone tinyShield run")
        _ = await manager.setUserScript(withId: adGuardExtra.id, disabledOnHost: "overlap.example", disabled: false)

        // Twitch + VAFT suppression still suppresses AdGuard Extra on Twitch
        await manager.setUserScript(vaft, isEnabled: true)
        await manager.refreshFromDiskForExecution()
        expect(names(for: "https://www.twitch.tv/test") == ["TwitchAdSolutions (vaft)"], "VAFT suppresses AdGuard Extra on Twitch")
        await manager.setUserScript(vaft, isEnabled: false)
        await manager.refreshFromDiskForExecution()
        expect(names(for: "https://www.twitch.tv/test").contains("AdGuard Extra"), "Twitch runs AdGuard Extra when VAFT is off")

        // Standalone tinyShield OFF: AdGuard Extra runs on both `hosts` and `tinyShieldDomains`, still skipped elsewhere
        await manager.setUserScript(tinyShield, isEnabled: false)
        await manager.refreshFromDiskForExecution()
        expect(names(for: "https://sub.1000logos.net/logo").contains("AdGuard Extra"), "with standalone tinyShield off, AdGuard Extra covers bundled tinyShield domains")
        expect(names(for: "https://facebook.com/").contains("AdGuard Extra"), "with standalone tinyShield off, AdGuard Extra still covers extra hosts")
        expect(!names(for: "https://apple.com/").contains("AdGuard Extra"), "with standalone tinyShield off, unrelated hosts still skip AdGuard Extra")

        // Version mismatch: falls back to *://*/* so new sites never silently break
        let mismatchedJSON = manifestJSON.replacingOccurrences(of: "\"1.1.41\"", with: "\"1.1.40\"")
        try Data(mismatchedJSON.utf8).write(to: scriptsDir.appendingPathComponent(AdGuardExtraHostManifest.fileName), options: .atomic)
        expect(names(for: "https://apple.com/").contains("AdGuard Extra"), "version mismatch must fall back to *://*/*")

        print("adguard extra host manifest tests passed")
    }
}
