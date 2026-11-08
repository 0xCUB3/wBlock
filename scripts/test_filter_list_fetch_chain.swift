import CryptoKit
import Foundation
import wBlockCoreService

final class ChainProtocol: URLProtocol {
    static var statuses: [Int] = []
    static var bodies: [Data?] = []
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let status = Self.statuses.isEmpty ? 500 : Self.statuses.removeFirst()
        let body = Self.bodies.isEmpty ? (status == 200 ? Data("||example.com^".utf8) : Data()) : (Self.bodies.removeFirst() ?? Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
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
        let crlf = Data("! Title: T\r\n!#unknown\r\n||a.com^\r\n".utf8)
        let saved = Data(FilterListContentProcessing.normalizedContent(from: String(decoding: crlf, as: UTF8.self)).utf8)
        check(FilterUpdateResponseClassifier.classify(statusCode: 200, responseData: crlf, localData: saved) == .unchangedContent, "CRLF body matches its saved form")
        check(FilterUpdateResponseClassifier.classify(statusCode: 200, responseData: crlf + Data("||b.com^".utf8), localData: saved) == .updatedContent, "CRLF body with a new rule")
        let installed = Data("! Version: 2.4.99.4\n||a.com^\n||b.com^".utf8)
        check(!FilterUpdateResponseClassifier.contentDiffers(remoteData: Data("! Version: 2.4.98.98\n||a.com^".utf8), localData: installed), "older mirror copy is not an update")
        check(FilterUpdateResponseClassifier.contentDiffers(remoteData: Data("! Version: 2.4.99.5\n||a.com^".utf8), localData: installed), "newer version is an update")
        check(FilterUpdateResponseClassifier.contentDiffers(remoteData: Data("! Version: 05 Sep 2026\n||a.com^".utf8), localData: Data("! Version: 06 Sep 2026\n||b.com^".utf8)), "dated versions fall back to content")
        do { reset([304]); let r = try await fetch(); check(!r.servedFallback && ChainProtocol.requests.count == 1, "304 stops without fallback") } catch { check(false, "304 threw") }
        do { reset([200, 200, 200], [Data("<html>challenge</html>".utf8), Data("<html>challenge</html>".utf8), Data("||ok.com^".utf8)]); let r = try await fetch(); check(r.servedFallback && ChainProtocol.requests.count == 3, "HTML then fallback") } catch { check(false, "HTML fallback threw") }
        do { reset([200, 200, 200], [Data("rate limit exceeded".utf8), Data("rate limit exceeded".utf8), Data("||ok.com^".utf8)]); let r = try await fetch(); check(r.servedFallback && ChainProtocol.requests.count == 3, "plain 200 retries then fallback") } catch { check(false, "plain 200 fallback threw") }
        do { reset([200, 200, 304], [Data("rate limit exceeded".utf8), Data("rate limit exceeded".utf8), Data()]); _ = try await fetch(); check(false, "fallback 304 returned success") } catch { check(ChainProtocol.requests.count == 3, "fallback 304 failed") }
        do { reset([404, 404, 200]); let r = try await fetch(); check(r.servedFallback && ChainProtocol.requests.count == 3, "404 fallback") } catch { check(false, "404 fallback threw") }
        do { reset([200]); let r = try await fetch(); check(!r.servedFallback && ChainProtocol.requests.count == 1, "primary success stops") } catch { check(false, "primary success threw") }
        do { reset([500, 500, 500]); _ = try await fetch(); check(false, "all failures returned") } catch { check(ChainProtocol.requests.count == 3, "all failures tried fallback") }
        reset([429, 429, 200]); do { _ = try await fetch() } catch { check(false, "validator case threw") }
        check(ChainProtocol.requests[0].value(forHTTPHeaderField: "If-None-Match") == "old", "validator on primary")
        check(ChainProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil, "no validator on fallback")
        // uBO diff updates run inside the chain, and one patch file serves every list.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func baseline(_ patch: String) -> URL {
            let url = dir.appendingPathComponent(UUID().uuidString)
            try? Data("! Diff-Path: ../patches/\(patch).patch#a\n||a.com^\n".utf8).write(to: url)
            return url
        }
        let patched = "! Diff-Path: ../patches/1.1.1.0.patch#a\n||a.com^\n||b.com^\n"
        let sha = Insecure.SHA1.hash(data: Data(patched.utf8)).map { String(format: "%02x", $0) }.joined()
        let patch = Data("diff name:a lines:2 checksum:\(sha.prefix(10))\na2 1\n||b.com^\n".utf8)
        let patches = FilterPatchCache(), oldBaseline = baseline("1.1.1.0")
        func deltaFetch(_ list: String, _ baselineURL: URL) async throws -> FilterListFetchResult {
            try await FilterListFetchChain.fetch(
                session: session, primaryURL: URL(string: "https://cdn.example/filters/\(list)")!, fallbackURLs: [],
                etag: "old", retryDelay: 0, diffBaselineURL: baselineURL, patches: patches)
        }
        do {
            reset([200], [patch])
            let first = try await deltaFetch("one.txt", oldBaseline), second = try await deltaFetch("two.txt", oldBaseline)
            check(first.response.statusCode == 200 && String(decoding: first.data, as: UTF8.self) == patched, "patch applied")
            check(first.response.value(forHTTPHeaderField: "ETag") == nil, "patched body has no validators")
            check(second.data == first.data, "second list patched")
            check(ChainProtocol.requests.map { $0.url!.absoluteString } == ["https://cdn.example/patches/1.1.1.0.patch"], "one patch request")
            reset([]); let deferred = try await deltaFetch("one.txt", baseline("2999.1.1.0"))
            check(deferred.response.statusCode == 304 && ChainProtocol.requests.isEmpty, "unpublished patch is not fetched")
            reset([404, 304]); let missing = try await FilterListFetchChain.fetch(
                session: session, primaryURL: primary, fallbackURLs: [], etag: "old", retryDelay: 0,
                diffBaselineURL: baseline("1.1.2.0"), patches: FilterPatchCache())
            check(missing.response.statusCode == 304 && ChainProtocol.requests.count == 2, "missing patch falls back to conditional GET")
            check(ChainProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "old", "fallback GET keeps validators")
        } catch { check(false, "delta fetch threw \(error)") }
        print("PASS")
    }
}
