import Foundation

@main
struct UserScriptDisplayMetadataTests {
    static func main() throws {
        for definition in BuiltInUserScripts.definitions {
            var script = UserScript(name: definition.name, url: URL(string: definition.url))
            script.description = definition.description
            let originalID = script.id
            let originalURL = script.url
            let expectedDescription = definition.description == "Default userscript"
                ? "Header description" : definition.description
            for version in ["1.0", "2.0"] {
                let content = header(version: version)
                // Prefetch parses a separate record; downloads and disk hydration reparse content.
                var prefetched = UserScript(name: script.name, url: script.url, content: content)
                prefetched.parseMetadata()
                expect(prefetched.name == definition.name, "prefetch keeps the catalog name")
                expect(prefetched.description == expectedDescription, "prefetch keeps curated description keys")
                script.description = prefetched.description
                let previous = script
                script.replaceContentAndParseMetadata(content)
                script.restoreDisplayMetadata(from: previous)
                expect(script.version == version && script.author == "Header author", "runtime metadata still refreshes")
                expect(script.matches == ["*://example.com/*"], "match directives still refresh")
                expect(script.updateURL == "https://example.com/script.meta.js", "header update URL still parses")
                expect(script.description == expectedDescription, "download keeps curated descriptions")
                script = try JSONDecoder().decode(UserScript.self, from: JSONEncoder().encode(script))
                script.replaceContentAndParseMetadata(content)
                BuiltInUserScripts.applyDisplayMetadata(to: &script)
                expect(script.name == definition.name && script.description == expectedDescription, "relaunch stays stable")
                expect(script.id == originalID && script.url == originalURL, "display policy preserves identity")
                if definition.description != "Default userscript" {
                    assertLocalizedKey(script.description, catalogKey: definition.description)
                }
            }
        }
        for (legacy, canonical) in BuiltInUserScripts.legacyBundledURLsByCanonical {
            var script = UserScript(name: "Old name", url: URL(string: legacy), content: header())
            script.parseMetadata()
            expect(script.description == BuiltInUserScripts.definition(for: URL(string: canonical))!.description,
                   "legacy bundled identities share curated metadata")
        }
        var custom = UserScript(name: "Fallback", url: URL(string: "https://example.com/custom.user.js"), content: header())
        custom.parseMetadata()
        expect(custom.name == "Header name" && custom.description == "Header description", "custom imports use header metadata")
        custom.name = "My name"
        custom.description = "My description"
        for description in ["My description", ""] {
            custom.description = description
            let persisted = custom
            custom.replaceContentAndParseMetadata(header(version: "3.0"))
            custom.restoreDisplayMetadata(from: persisted)
            expect(custom.name == "My name" && custom.description == description, "custom edits, including empty descriptions, survive refresh")
            expect(custom.version == "3.0", "custom version still refreshes")
            expect(!BuiltInUserScripts.applyDisplayMetadata(to: &custom), "startup never changes custom display edits")
        }
        var local = UserScript(name: "Local", content: header())
        local.isLocal = true
        local.parseMetadata()
        expect(local.description == "Header description", "local source edits retain header behavior")
        print("PASS: built-in display metadata stays localizable; custom headers and edits remain intact")
    }

    private static func header(version: String = "1.0") -> String {
        """
        // ==UserScript==
        // @name Header name
        // @description Header description
        // @author Header author
        // @version \(version)
        // @match *://example.com/*
        // @updateURL https://example.com/script.meta.js
        // ==/UserScript==
        console.log(1);
        """
    }

    private static func assertLocalizedKey(_ key: String, catalogKey: String) {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let bundle = Bundle(path: root.appendingPathComponent("wBlock/pl.lproj").path)!
        let expected = NSLocalizedString(catalogKey, bundle: bundle, comment: "")
        if catalogKey == BuiltInUserScripts.tinyShieldDescription {
            expect(expected != catalogKey, "fixture uses an existing Polish translation")
        }
        expect(NSLocalizedString(key, bundle: bundle, comment: "") == expected, "parsed description still resolves the catalog translation")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
