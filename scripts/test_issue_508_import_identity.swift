import Foundation
import wBlockCoreService

@main
struct Issue508ImportIdentityTests {
    static func main() {
        let source = """
        // ==UserScript==
        // @name Source Name
        // @description Source description
        // @match https://example.com/*
        // ==/UserScript==
        console.log("source");
        """
        let identity = UserScriptImportIdentity.forContent(source)

        var imported = UserScript(name: "Display Override", content: source)
        imported.isLocal = true
        imported.localImportIdentity = identity
        imported.description = "Preserved description"
        imported.category = .custom

        var reimport = UserScript(name: "Source Name", content: source)
        reimport.isLocal = true
        reimport.localImportIdentity = identity

        expect(
            UserScript.matchesLocalImport(
                existing: imported,
                stableIdentity: reimport.localImportIdentity!,
                canonicalName: reimport.name
            ),
            "a display-name override must not prevent replacement"
        )
        expect(imported.description == "Preserved description", "existing metadata must remain available to replacement")
        expect(imported.category == .custom, "existing category must remain available to replacement")

        var legacy = UserScript(name: "Legacy Name", content: source)
        legacy.isLocal = true
        expect(
            UserScript.matchesLocalImport(existing: legacy, stableIdentity: identity, canonicalName: "Legacy Name"),
            "legacy local scripts must retain name-based replacement"
        )

        var remote = UserScript(name: "Display Override", url: URL(string: "https://remote.example/script.js"), content: source)
        remote.isLocal = false
        remote.localImportIdentity = identity
        expect(
            !UserScript.matchesLocalImport(existing: remote, stableIdentity: identity, canonicalName: remote.name),
            "remote scripts with identical content must not be conflated"
        )

        print("PASS: issue 508 local import identity")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
