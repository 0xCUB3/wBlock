import Foundation

@MainActor
private final class DownloadFixture {
    enum Reply {
        case content(Data, mime: String = "application/javascript", redirect: URL? = nil)
        case failure(Error)
    }
    var replies: [Reply]
    var requests: [URL] = []
    var accepted: [UserScriptDownload.Content] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func fetch(_ url: URL) async throws -> UserScriptDownload.Content {
        let result = try await UserScriptDownload.fetch(from: url) { endpoint in
            self.requests.append(endpoint)
            guard !self.replies.isEmpty else { throw URLError(.resourceUnavailable) }
            switch self.replies.removeFirst() {
            case .failure(let error): throw error
            case .content(let data, let mime, let redirect):
                return (data, HTTPURLResponse(url: redirect ?? endpoint, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": mime, "Last-Modified": "Wed, 01 Oct 2025 00:00:00 GMT"])!)
            }
        }
        // Represents the source cache's boundary: failed validation never returns cacheable content.
        accepted.append(result)
        return result
    }
}

@main
struct UserScriptDownloadTests {
    private static let valid = Data("""
        // ==UserScript==
        // @name Upstream name
        // @description Header description
        // @version 2.0
        // @updateURL https://example.com/version.meta.js
        // @downloadURL https://example.com/source.user.js
        // ==/UserScript==
        const marker = 'checking your browser';
        """.utf8)

    @MainActor
    static func main() async throws {
        let twitch = URL(string: "https://raw.githubusercontent.com/ryanbr/TwitchAdSolutions/master/vaft/vaft.user.js")!
        let allowed = [twitch, URL(string: BuiltInUserScripts.darkReaderURL)!,
                       URL(string: BuiltInUserScripts.deArrowURL)!, URL(string: BuiltInUserScripts.playerCleanerURL)!,
                       URL(string: BuiltInUserScripts.tubeCleanerURL)!]
        for primary in allowed {
            let parts = URLComponents(url: primary, resolvingAgainstBaseURL: false)!.percentEncodedPath.split(separator: "/")
            let expected = URL(string: "https://cdn.jsdelivr.net/gh/\(parts[0])/\(parts[1])@\(parts[2])/\(parts.dropFirst(3).joined(separator: "/"))")!
            expect(UserScriptDownload.fallbackURLs(for: primary) == [expected], "mirror preserves exact owner, repository, ref, and encoded path")
            let fixture = DownloadFixture([.failure(URLError(.badServerResponse)), .content(valid)])
            let result = try await fixture.fetch(primary)
            expect(fixture.requests == [primary, expected] && result.sourceURL == expected, "failed primary tries the mirror once")
            var script = UserScript(name: "Before", url: primary)
            let id = script.id
            script.replaceContentAndParseMetadata(result.text)
            expect(script.url == primary && script.id == id, "mirror does not change subscription identity")
            expect(script.updateURL == "https://example.com/version.meta.js" && script.downloadURL == "https://example.com/source.user.js",
                   "mirror transport does not rewrite authored update/download metadata")
        }
        let blocked = [
            "http://raw.githubusercontent.com/ryanbr/TwitchAdSolutions/master/vaft/vaft.user.js",
            twitch.absoluteString + "?token=anything", twitch.absoluteString + "#fragment",
            "https://user:password@raw.githubusercontent.com/ryanbr/TwitchAdSolutions/master/vaft/vaft.user.js",
            "https://raw.githubusercontent.com/ryanbr/TwitchAdSolutions/main/vaft/vaft.user.js",
            "https://raw.githubusercontent.com/ryanbr/TwitchAdSolutions/refs/heads/master/vaft/vaft.user.js",
            "https://raw.githubusercontent.com/ryanbr/TwitchAdSolutions/master/vaft/vaft.meta.js",
            "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/other/dist/other.user.js",
            "https://raw.githubusercontent.com/other/wBlock-userscripts/main/packages/tube-cleaner/dist/tube-cleaner.user.js"
        ] + BuiltInUserScripts.definitions.map(\.url).filter { !allowed.contains(URL(string: $0)!) }
        for source in blocked {
            let url = URL(string: source)!
            expect(UserScriptDownload.fallbackURLs(for: url).isEmpty, "no trust expansion to custom subscriptions or altered sources")
            let fixture = DownloadFixture([.failure(URLError(.badServerResponse)), .content(valid)])
            await expectFailure(fixture, url: url)
            expect(fixture.requests == [url], "custom/other sources get no extra request")
        }
        let mirror = UserScriptDownload.fallbackURLs(for: twitch)[0]
        let success = DownloadFixture([.content(valid), .failure(URLError(.badServerResponse))])
        let result = try await success.fetch(twitch)
        expect(success.requests == [twitch] && result.sourceURL == twitch, "valid primary stops the chain")

        let invalid: [DownloadFixture.Reply] = [
            .content(Data()), .content(Data([0xff, 0xfe])), .content(Data("404: Not Found".utf8)),
            .content(Data("console.log('not a userscript');".utf8)),
            .content(Data("// ==UserScript==\n// @name Incomplete".utf8)),
            .content(Data("<!doctype html><html>Ordinary error</html>".utf8)),
            .content(Data("\u{FEFF} <!-- comment --><?xml version='1.0'?><HTML>checking your browser</HTML>".utf8)),
            .content(Data("<html>\n".utf8) + valid + Data("\n</html>".utf8)),
            .content(valid, mime: "text/html"),
            .content(valid, redirect: URL(string: "https://unexpected.example/source.user.js")),
            .content(valid, redirect: URL(string: twitch.absoluteString.replacingOccurrences(of: "/master/", with: "/main/")))
        ]
        for reply in invalid {
            let recovered = DownloadFixture([reply, .content(valid)])
            _ = try await recovered.fetch(twitch)
            expect(recovered.requests == [twitch, mirror] && recovered.accepted.count == 1, "invalid primary is not cached; valid mirror recovers")
            let failed = DownloadFixture([.failure(URLError(.badServerResponse)), reply])
            await expectFailure(failed, url: twitch)
            expect(failed.requests == [twitch, mirror], "invalid mirror is never accepted or retried indefinitely")
        }
        let bothInvalid = DownloadFixture([invalid[5], invalid[2]])
        await expectFailure(bothInvalid, url: twitch)
        expect(bothInvalid.requests.count == 2, "all invalid responses terminate")
        for error in [CancellationError() as Error, URLError(.cancelled)] {
            let fixture = DownloadFixture([.failure(error), .content(valid)])
            await expectFailure(fixture, url: twitch)
            expect(fixture.requests == [twitch], "cancellation never starts a mirror request")
        }
        let cancelled = DownloadFixture([.content(valid)])
        let task = Task { try await cancelled.fetch(twitch) }
        task.cancel()
        do { _ = try await task.value; expect(false, "cancelled task returned content") } catch {}
        expect(cancelled.requests.isEmpty && cancelled.accepted.isEmpty, "already-cancelled task never fetches or caches")

        let customURL = URL(string: "https://example.com/custom.js")!
        let custom = DownloadFixture([.content(Data("console.log('custom plain JS');".utf8))])
        _ = try await custom.fetch(customURL)
        expect(custom.requests == [customURL], "custom plain-JS import policy remains unchanged")
        print("PASS: exact built-in mirror chain; invalid content and redirects rejected before caching; custom trust unchanged")
    }

    @MainActor
    private static func expectFailure(_ fixture: DownloadFixture, url: URL) async {
        do { _ = try await fixture.fetch(url); expect(false, "expected download failure") } catch {}
        expect(fixture.accepted.isEmpty, "failed download must not return cacheable content")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
}
