
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
        expect(script.matches(url: "http://namemc.com/"), "*:// should match http")
        expect(!script.matches(url: "ftp://namemc.com/"), "*:// must not match ftp (#751)")
        expect(!UserScript.matchesMatchPattern("*://namemc.com/*", url: "ftp://namemc.com/x"), "structured *:// must not match ftp")
        expect(!UserScript.matchesMatchPattern("*://namemc.com/*?a=*", url: "ftp://namemc.com/x?a=1"), "regex fallback *:// must not match ftp")
        expect(UserScript.matchesMatchPattern("ftp://namemc.com/*", url: "ftp://namemc.com/x"), "explicit ftp:// still matches ftp")

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

        let padding = (0..<100).map { "https://unused\($0).invalid/*" }
        let patterns = ["*://*.example.org/private*", "https://exact.invalid:8443/*", "https://foo*bar.invalid/*", "https://*/*allowed*", "legacy*"]
        var indexed = UserScript(name: "indexed")
        indexed.matches = padding + patterns
        for url in ["https://sub.example.org/private?a=1", "ftp://sub.example.org/private", "https://example.org/public", "https://exact.invalid:8443/x", "https://exact.invalid/x", "https://fooxbar.invalid/x", "https://other.invalid/allowed", "https://other.invalid/no", "https://evil-example.org/private"] {
            let linear = indexed.matches.contains { UserScript.matchesMatchPattern($0, url: url) }
            expectEqual(indexed.matches(url: url), linear, "indexed match must equal linear match for \(url)")
        }
        indexed.matches = padding + ["https://changed.invalid/*"]
        expect(indexed.matches(url: "https://changed.invalid/"), "same-ID pattern mutation rebuilds index")
        expect(!indexed.matches(url: "https://sub.example.org/private"), "old indexed hosts cannot survive mutation")
        indexed.excludeMatches = padding + ["https://changed.invalid/*"]
        expect(!indexed.matches(url: "https://changed.invalid/"), "large exclude list uses its own index")
        indexed.excludeMatches = padding
        expect(indexed.matches(url: "https://changed.invalid/"), "exclude mutation rebuilds independently")

        var connectScript = UserScript(name: "connect", content: "// ==UserScript==\n// @connect example.org\n//\t@connect\tlocalhost\n// ==/UserScript==\n// @connect *")
        expectEqual(connectScript.connect, ["example.org", "localhost"], "only metadata grants network hosts")
        expectEqual(UserScript(name: "legacy").connect, ["self"], "missing connect defaults to same-host only")
        connectScript.content = "// ==UserScript==\n// @connect *\n// ==/UserScript=="
        expectEqual(connectScript.connect, ["*"], "source mutation invalidates connect metadata cache")
        connectScript.content = "// ==UserScript==\n// @connect\n// ==/UserScript=="
        expectEqual(connectScript.connect, [], "empty declared connect fails closed")
        let page = URL(string: "https://page.invalid/")!
        for (entries, target, allowed) in [
            (["example.org"], "https://sub.example.org/x", true),
            (["example.org"], "https://evil-example.org/x", false),
            (["example.org"], "https://example.org.evil/x", false),
            (["self"], "https://page.invalid:8443/x", true),
            (["self"], "https://sub.page.invalid/x", false),
            (["localhost"], "http://localhost:8080/x", true),
            (["*"], "file:///etc/passwd", false),
            (["*"], "https://user:secret@example.org/", false),
            (["*"], "https://anywhere.invalid/", true),
            (["https://example.org"], "https://example.org/", false),
            ([String](), "https://page.invalid/", false)
        ] {
            expectEqual(UserScriptConnectPolicy(entries: entries, pageURL: page).allows(URL(string: target)!), allowed, "connect policy for \(target) with \(entries)")
        }

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let redirectResponse = HTTPURLResponse(url: page, statusCode: 302, httpVersion: nil, headerFields: nil)!
        for (mode, target, allowed) in [("follow", page, true), ("follow", URL(string: "https://outside.invalid/")!, false), ("manual", page, false), ("error", page, false)] {
            let task = session.dataTask(with: page)
            let delegate = GMRedirectPolicyDelegate(policy: UserScriptConnectPolicy(entries: ["self"], pageURL: page), redirect: mode)
            var called = false
            delegate.urlSession(session, task: task, willPerformHTTPRedirection: redirectResponse, newRequest: URLRequest(url: target)) { request in
                called = true
                expectEqual(request != nil, allowed, "native redirect policy for \(target) in \(mode) mode")
            }
            expect(called, "native redirect callback must always complete")
            task.cancel()
        }

        let crossHost = URL(string: "https://allowed.invalid/")!
        var authenticated = URLRequest(url: crossHost)
        authenticated.setValue("secret", forHTTPHeaderField: "Authorization")
        authenticated.setValue("session=secret", forHTTPHeaderField: "Cookie")
        let redirectTask = session.dataTask(with: page)
        GMRedirectPolicyDelegate(policy: UserScriptConnectPolicy(entries: ["*"], pageURL: page), redirect: "follow")
            .urlSession(session, task: redirectTask, willPerformHTTPRedirection: redirectResponse, newRequest: authenticated) { request in
                expectEqual(request?.url, crossHost, "approved cross-host redirect may proceed")
                expect(request?.value(forHTTPHeaderField: "Authorization") == nil, "native redirect strips cross-host authorization")
                expect(request?.value(forHTTPHeaderField: "Cookie") == nil, "native redirect strips cross-host cookie header")
            }
        redirectTask.cancel()

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
