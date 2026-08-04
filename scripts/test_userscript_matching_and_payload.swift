
import Foundation

@main
struct UserScriptMatchingAndPayloadTests {
    static func main() {
        var metadataLines: [String] = [
            "// ==UserScript==",
            "// @name tinyShield-sized test",
            "// @run-at document-start"
        ]
        for index in 0..<6_000 {
            metadataLines.append("// @match *://example\(index).invalid/*")
        }
        metadataLines.append("// @match *://namemc.com/*")
        metadataLines.append("// @match *://*.namemc.com/*")
        metadataLines.append("// ==/UserScript==")

        let requiredPrefix = "/* required dependency */\n"
        let body = "(() => { window.__wBlockPayloadTest = true; })();\n"
        let source = requiredPrefix + metadataLines.joined(separator: "\n") + "\n" + body

        var script = UserScript(name: "fallback", content: source)
        script.parseMetadata()

        expectEqual(script.name, "tinyShield-sized test", "metadata name should parse")
        expectEqual(script.runAt, "document-start", "run-at should parse")
        expect(script.matches(url: "https://namemc.com/profile/example"), "exact namemc match should work")
        expect(script.matches(url: "https://sub.namemc.com/profile/example"), "wildcard namemc match should work")
        expect(!script.matches(url: "https://unrelated.invalid/"), "unrelated host should not match")

        let executable = script.executableContent
        expectEqual(executable, requiredPrefix + body, "executable payload should remove metadata and keep required prefix")
        expect(source.utf8.count > 128 * 1024, "test source should exceed the ordinary inline cap")
        expect(executable.utf8.count < 128 * 1024, "stripped executable payload should fit the ordinary inline cap")

        let plainScript = "console.log('plain');"
        expectEqual(
            UserScript.executableContent(from: plainScript),
            plainScript,
            "scripts without metadata should be unchanged"
        )

        let storageGrants = [
            "GM_getValue", "GM_setValue", "GM_deleteValue", "GM_listValues",
            "GM_addValueChangeListener", "GM_removeValueChangeListener",
            "GM.getValue", "GM.setValue", "GM.deleteValue", "GM.listValues",
            "GM.addValueChangeListener", "GM.removeValueChangeListener"
        ]
        for grant in storageGrants {
            var storageScript = UserScript(name: grant)
            storageScript.grant = [grant]
            expect(storageScript.usesGMStorage, "\(grant) should request the storage snapshot")
        }
        for grants in [[], ["none"], ["GM_xmlhttpRequest"], ["unsafeWindow"]] {
            var storageScript = UserScript(name: grants.joined(separator: ","))
            storageScript.grant = grants
            expect(!storageScript.usesGMStorage, "\(grants) should skip the storage snapshot")
        }

        let payloadCache = UserScriptPayloadDataCache()
        var payloadBuilds = 0
        let firstPayload = payloadCache.data(for: "script", source: "first") { source in
            payloadBuilds += 1
            return "prepared-\(source)"
        }
        let cachedPayload = payloadCache.data(for: "script", source: "first") { _ in
            payloadBuilds += 1
            return nil
        }
        let revisedPayload = payloadCache.data(for: "script", source: "other") { source in
            payloadBuilds += 1
            return "prepared-\(source)"
        }
        expectEqual(firstPayload, Data("prepared-first".utf8), "payload cache should prepare content")
        expectEqual(cachedPayload, firstPayload, "payload cache should reuse prepared bytes")
        expectEqual(revisedPayload, Data("prepared-other".utf8), "changed source should replace cached bytes")
        expectEqual(payloadBuilds, 2, "payload cache should prepare each source revision once")

        print("PASS: userscript matching and payload")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fputs("FAIL: \(message)\nactual: \(actual)\nexpected: \(expected)\n", stderr)
            exit(1)
        }
    }
}
