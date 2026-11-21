import CryptoKit
import Foundation
import wBlockCoreService

final class ChainProtocol: URLProtocol {
    static var statuses: [Int] = []
    static var bodies: [Data?] = []
    static var requests: [URLRequest] = []
    /// Requests to these hosts wait until `releaseHeld` answers them.
    static var holdHosts: Set<String> = []
    static var held: [ChainProtocol] = []
    /// Held requests that were cancelled by the client.
    static var stopped = 0
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let hold = Self.holdHosts.contains(request.url?.host ?? "")
        if hold { Self.held.append(self) }
        Self.lock.unlock()
        if hold { return }
        let status = Self.statuses.isEmpty ? 500 : Self.statuses.removeFirst()
        let body = Self.bodies.isEmpty ? (status == 200 ? Data("||example.com^".utf8) : Data()) : (Self.bodies.removeFirst() ?? Data())
        respond(status: status, body: body)
    }
    override func stopLoading() {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if let index = Self.held.firstIndex(where: { $0 === self }) {
            Self.held.remove(at: index)
            Self.stopped += 1
        }
    }
    private func respond(status: Int, body: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
    }
    static func releaseHeld(_ body: Data) {
        lock.lock()
        let waiting = held
        held = []
        lock.unlock()
        for instance in waiting { instance.respond(status: 200, body: body) }
    }
}

func waitUntil(_ condition: () -> Bool) async {
    var attempts = 0
    while !condition() && attempts < 300 {
        attempts += 1
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@main struct FetchChainTest {
    static func main() async {
        func check(_ value: Bool, _ message: String) { if !value { fputs("FAIL: \(message)\n", stderr); exit(1) } }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ChainProtocol.self]
        let session = URLSession(configuration: config)
        let primary = URL(string: "https://primary.example/list.txt")!, fallback = URL(string: "https://fallback.example/list.txt")!
        func reset(_ statuses: [Int], _ bodies: [Data?] = []) { ChainProtocol.statuses = statuses; ChainProtocol.bodies = bodies; ChainProtocol.requests = [] }
        func fetch() async throws -> FilterListFetchResult {
            try await FilterListFetchChain.fetch(session: session, primaryURL: primary, fallbackURLs: [fallback], etag: "old", retryDelay: 0)
        }
        check(FilterUpdateResponseClassifier.isRetryable(statusCode: 403), "403 retry")
        check(FilterUpdateResponseClassifier.isRetryable(statusCode: 404), "404 retry")
        check(FilterUpdateResponseClassifier.isRetryable(statusCode: 429), "429 retry")
        check(FilterUpdateResponseClassifier.isRetryable(statusCode: 500), "500 retry")
        check(FilterUpdateResponseClassifier.looksLikeFilterListData(Data("||example.com^".utf8)), "filter data")
        check(!FilterUpdateResponseClassifier.looksLikeFilterListData(Data("<html>challenge".utf8)), "HTML")
        check(!FilterUpdateResponseClassifier.looksLikeFilterListData(Data("404: Not Found".utf8)), "404 body")
        check(!FilterUpdateResponseClassifier.looksLikeFilterListData(Data()), "empty")
        for scalar in ["é", "日", "😀"] {
            for split in 1..<scalar.utf8.count {
                let text = String(repeating: "!", count: 2048 - split) + scalar + "\n||example.com^"
                check(FilterUpdateResponseClassifier.looksLikeFilterListData(Data(text.utf8)), "UTF-8 sniff boundary \(scalar) \(split)")
            }
        }
        check(!FilterUpdateResponseClassifier.looksLikeFilterListData(Data([0xff, 0xff])), "invalid short UTF-8")
        check(FilterUpdateResponseClassifier.classify(statusCode: 200, responseData: Data("<html>challenge</html>".utf8), localData: nil) == .invalidContent, "HTML invalid")
        check(FilterUpdateResponseClassifier.classify(statusCode: 200, responseData: Data("404: Not Found".utf8), localData: nil) == .invalidContent, "404 body invalid")
        var readLocal = false
        check(FilterUpdateResponseClassifier.classify(statusCode: 304, responseData: nil, localData: { readLocal = true; return nil }()) == .notModified && !readLocal, "304 skips the saved list")
        let crlf = Data("! Title: T\r\n!#unknown\r\n||a.com^\r\n".utf8)
        let saved = Data(FilterListContentProcessing.normalizedContent(from: String(decoding: crlf, as: UTF8.self)).utf8)
        check(FilterUpdateResponseClassifier.classify(statusCode: 200, responseData: crlf, localData: saved) == .unchangedContent, "CRLF body matches its saved form")
        check(FilterUpdateResponseClassifier.classify(statusCode: 200, responseData: crlf + Data("||b.com^".utf8), localData: saved) == .updatedContent, "CRLF body with a new rule")
        let installed = Data("! Version: 2.4.99.4\n||a.com^\n||b.com^".utf8)
        let olderCopy = Data("! Version: 2.4.98.98\n||a.com^".utf8)
        check(!FilterUpdateResponseClassifier.contentDiffers(remoteData: olderCopy, localData: installed, usedFallbackMirror: true), "older fallback mirror copy is not an update")
        check(FilterUpdateResponseClassifier.contentDiffers(remoteData: olderCopy, localData: installed), "older primary copy is a rollback and applies")
        check(FilterUpdateResponseClassifier.classify(statusCode: 200, responseData: olderCopy, localData: installed, usedFallbackMirror: true) == .unchangedContent, "classify passes the fallback guard through")
        check(FilterUpdateResponseClassifier.contentDiffers(remoteData: Data("! Version: 2.4.99.5\n||a.com^".utf8), localData: installed), "newer version is an update")
        check(FilterUpdateResponseClassifier.contentDiffers(remoteData: Data("! Version: 05 Sep 2026\n||a.com^".utf8), localData: Data("! Version: 06 Sep 2026\n||b.com^".utf8)), "dated versions fall back to content")
        // A saved list that includes other files is stored expanded. Its digest of the
        // normalized, unexpanded body is what a later check compares against.
        let remoteWithInclude = "! Version: 1.0\n||a.com^\n!#include child.txt\n"
        let expandedLocal = Data("! Version: 1.0\n||a.com^\n||included.example^\n".utf8)
        let includeDigest = FilterUpdateResponseClassifier.sha256Hex(
            Data(FilterListContentProcessing.normalizedContent(from: remoteWithInclude).utf8))
        check(FilterUpdateResponseClassifier.classify(statusCode: 200, responseData: Data(remoteWithInclude.utf8), localData: expandedLocal, localNormalizedDigest: includeDigest) == .unchangedContent, "expanded list matches its stored digest")
        check(FilterUpdateResponseClassifier.classify(statusCode: 200, responseData: Data(remoteWithInclude.utf8), localData: expandedLocal) == .updatedContent, "without a digest, expanded bytes compare as before")
        check(FilterUpdateResponseClassifier.classify(statusCode: 200, responseData: Data((remoteWithInclude + "||b.com^\n").utf8), localData: expandedLocal, localNormalizedDigest: includeDigest) == .updatedContent, "a changed body differs from the stored digest")
        do { reset([304]); let r = try await fetch(); check(!r.servedFallback && ChainProtocol.requests.count == 1, "304 stops without fallback") } catch { check(false, "304 threw") }
        do { reset([200, 200, 200], [Data("<html>challenge</html>".utf8), Data("<html>challenge</html>".utf8), Data("||ok.com^".utf8)]); let r = try await fetch(); check(r.servedFallback && r.usedFallbackMirror && ChainProtocol.requests.count == 3, "HTML then fallback") } catch { check(false, "HTML fallback threw") }
        do { reset([200, 200, 200], [Data("rate limit exceeded".utf8), Data("rate limit exceeded".utf8), Data("||ok.com^".utf8)]); let r = try await fetch(); check(r.servedFallback && ChainProtocol.requests.count == 3, "plain 200 retries then fallback") } catch { check(false, "plain 200 fallback threw") }
        do { reset([200, 200, 304], [Data("rate limit exceeded".utf8), Data("rate limit exceeded".utf8), Data()]); _ = try await fetch(); check(false, "fallback 304 returned success") } catch { check(ChainProtocol.requests.count == 3, "fallback 304 failed") }
        do { reset([404, 404, 200]); let r = try await fetch(); check(r.servedFallback && ChainProtocol.requests.count == 3, "404 fallback") } catch { check(false, "404 fallback threw") }
        do { reset([200]); let r = try await fetch(); check(!r.servedFallback && ChainProtocol.requests.count == 1, "primary success stops") } catch { check(false, "primary success threw") }
        do { reset([500, 500, 500]); _ = try await fetch(); check(false, "all failures returned") } catch { check(ChainProtocol.requests.count == 3, "all failures tried fallback") }
        reset([429, 429, 200]); do { _ = try await fetch() } catch { check(false, "validator case threw") }
        check(ChainProtocol.requests[0].value(forHTTPHeaderField: "If-None-Match") == "old", "validator on primary")
        check(ChainProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil, "no validator on fallback")

        // A non-retryable status fails at once: no second attempt and no retry pause.
        let started = Date()
        do {
            reset([410])
            _ = try await FilterListFetchChain.fetch(session: session, primaryURL: primary, fallbackURLs: [], retryDelay: 30)
            check(false, "410 returned success")
        } catch {
            check(ChainProtocol.requests.count == 1 && Date().timeIntervalSince(started) < 5, "410 fails without a retry pause")
        }
        do {
            reset([401, 200])
            let rescued = try await FilterListFetchChain.fetch(session: session, primaryURL: primary, fallbackURLs: [fallback], retryDelay: 30)
            check(rescued.servedFallback && ChainProtocol.requests.count == 2 && Date().timeIntervalSince(started) < 5, "401 still reaches the fallback without a pause")
        } catch { check(false, "401 fallback threw") }

        // Cancelling during the retry pause stops the chain before any fallback is tried.
        do {
            reset([500, 200, 200])
            let task = Task {
                try await FilterListFetchChain.fetch(session: session, primaryURL: primary, fallbackURLs: [fallback, URL(string: "https://second.example/list.txt")!], retryDelay: 30)
            }
            await waitUntil { ChainProtocol.requests.count == 1 }
            try await Task.sleep(nanoseconds: 200_000_000)
            task.cancel()
            do {
                _ = try await task.value
                check(false, "cancelled fetch returned success")
            } catch {
                check(error is CancellationError, "cancelled fetch throws CancellationError")
            }
            check(ChainProtocol.requests.count == 1, "cancelled fetch walks no fallback")
        } catch { check(false, "cancellation setup threw") }

        // The first fallback answers while the primary is still waiting, and the primary is cancelled.
        do {
            ChainProtocol.holdHosts = ["primary.example"]; ChainProtocol.held = []; ChainProtocol.stopped = 0
            reset([200])
            let hedged = try await FilterListFetchChain.fetch(
                session: session, primaryURL: primary, fallbackURLs: [fallback],
                retryDelay: 0, hedgedFallback: true, hedgeDelay: 0.2)
            check(hedged.usedFallbackMirror && hedged.sourceURL == fallback, "hedged fallback answers while the primary waits")
            await waitUntil { ChainProtocol.stopped == 1 }
            check(ChainProtocol.stopped == 1, "the losing primary request is cancelled")
            ChainProtocol.holdHosts = []
        } catch { check(false, "hedged fetch threw") }

        // uBO diff updates run inside the chain, and one patch file serves every list.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func baseline(_ patch: String) -> URL {
            let url = dir.appendingPathComponent(UUID().uuidString)
            try? Data("! Diff-Path: ../patches/\(patch).patch#a\n||a.com^\n".utf8).write(to: url)
            return url
        }
        func patchBody(_ name: String) -> (body: Data, patched: String) {
            let patched = "! Diff-Path: ../patches/\(name).patch#a\n||a.com^\n||b.com^\n"
            let sha = Insecure.SHA1.hash(data: Data(patched.utf8)).map { String(format: "%02x", $0) }.joined()
            return (Data("diff name:a lines:2 checksum:\(sha.prefix(10))\na2 1\n||b.com^\n".utf8), patched)
        }
        func deltaFetch(_ list: String, _ baselineURL: URL, _ cache: FilterPatchCache) async throws -> FilterListFetchResult {
            try await FilterListFetchChain.fetch(
                session: session, primaryURL: URL(string: "https://cdn.example/filters/\(list)")!, fallbackURLs: [],
                etag: "old", retryDelay: 0, diffBaselineURL: baselineURL, patches: cache)
        }
        let patches = FilterPatchCache(), oldBaseline = baseline("1.1.1.0")
        do {
            let (patch, patched) = patchBody("1.1.1.0")
            reset([200], [patch])
            let first = try await deltaFetch("one.txt", oldBaseline, patches), second = try await deltaFetch("two.txt", oldBaseline, patches)
            check(first.response.statusCode == 200 && String(decoding: first.data, as: UTF8.self) == patched, "patch applied")
            check(first.response.value(forHTTPHeaderField: "ETag") == nil, "patched body has no validators")
            check(second.data == first.data, "second list patched")
            check(ChainProtocol.requests.map { $0.url!.absoluteString } == ["https://cdn.example/patches/1.1.1.0.patch"], "one patch request")
            reset([]); let deferred = try await deltaFetch("one.txt", baseline("2999.1.1.0"), patches)
            check(deferred.response.statusCode == 304 && ChainProtocol.requests.isEmpty, "unpublished patch is not fetched")
            reset([404, 304]); let missing = try await FilterListFetchChain.fetch(
                session: session, primaryURL: primary, fallbackURLs: [], etag: "old", retryDelay: 0,
                diffBaselineURL: baseline("1.1.2.0"), patches: FilterPatchCache())
            check(missing.response.statusCode == 304 && ChainProtocol.requests.count == 2, "missing patch falls back to conditional GET")
            check(ChainProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "old", "fallback GET keeps validators")
        } catch { check(false, "delta fetch threw \(error)") }

        // Patch downloads are reference-counted. A waiter that cancels while another
        // still waits leaves the shared download running. The last one stops it.
        do {
            ChainProtocol.holdHosts = ["cdn.example"]; ChainProtocol.held = []; ChainProtocol.requests = []; ChainProtocol.stopped = 0
            let (body, patched) = patchBody("1.1.5.0")
            let shared = FilterPatchCache()
            let first = Task { try await deltaFetch("one.txt", baseline("1.1.5.0"), shared) }
            await waitUntil { !ChainProtocol.requests.isEmpty }
            let second = Task { try await deltaFetch("two.txt", baseline("1.1.5.0"), shared) }
            try await Task.sleep(nanoseconds: 300_000_000)
            first.cancel()
            try await Task.sleep(nanoseconds: 200_000_000)
            check(ChainProtocol.stopped == 0, "one cancelled waiter keeps the shared patch download running")
            ChainProtocol.releaseHeld(body)
            let joined = try await second.value
            check(String(decoding: joined.data, as: UTF8.self) == patched, "the remaining waiter receives the patch")
            check(ChainProtocol.requests.count == 1, "both lists share one patch request")
            do {
                _ = try await first.value
                check(false, "cancelled waiter returned success")
            } catch {
                check(error is CancellationError, "cancelled waiter throws CancellationError")
            }

            ChainProtocol.requests = []; ChainProtocol.stopped = 0
            let solitary = FilterPatchCache()
            let three = Task { try await deltaFetch("three.txt", baseline("1.1.6.0"), solitary) }
            let four = Task { try await deltaFetch("four.txt", baseline("1.1.6.0"), solitary) }
            await waitUntil { ChainProtocol.requests.count == 1 }
            try await Task.sleep(nanoseconds: 300_000_000)
            three.cancel()
            try await Task.sleep(nanoseconds: 200_000_000)
            check(ChainProtocol.stopped == 0, "a cancelled waiter with another waiting does not stop the patch")
            four.cancel()
            await waitUntil { ChainProtocol.stopped == 1 }
            check(ChainProtocol.stopped == 1, "the last cancelled waiter stops the patch request")
            _ = try? await three.value
            _ = try? await four.value
            ChainProtocol.holdHosts = []
        } catch { check(false, "patch cancellation setup threw \(error)") }

        // Lists declare their refresh interval in the header as `! Expires:`.
        check(FilterListFetchChain.parseExpiresInterval(from: "! Expires: 4 days\n") == 4 * 86_400, "4 days")
        check(FilterListFetchChain.parseExpiresInterval(from: "! Expires: 1 day (update frequency)\n") == 86_400, "1 day with a note")
        check(FilterListFetchChain.parseExpiresInterval(from: "! Expires: 12 hours\r\n") == 12 * 3_600, "12 hours with CRLF")
        check(FilterListFetchChain.parseExpiresInterval(from: "!Expires: 6h\n") == 6 * 3_600, "6h without a space")
        check(FilterListFetchChain.parseExpiresInterval(from: "! Title: x\n! expires: 4d\n") == 4 * 86_400, "4d after another field, any case")
        check(FilterListFetchChain.parseExpiresInterval(from: "! Expires: 30 minutes\n") == 3_600, "short intervals clamp to an hour")
        check(FilterListFetchChain.parseExpiresInterval(from: "! Expires: 60 days\n") == 14 * 86_400, "long intervals clamp to fourteen days")
        check(FilterListFetchChain.parseExpiresInterval(from: "! Diff-Expires: 2 days\n") == nil, "Diff-Expires is not Expires")
        check(FilterListFetchChain.parseExpiresInterval(from: "! Expires: soon\n") == nil, "unparseable value")
        check(FilterListFetchChain.parseExpiresInterval(from: "! Title: x\n") == nil, "no Expires field")
        print("PASS")
    }
}
