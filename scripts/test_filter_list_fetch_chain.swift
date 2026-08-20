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
        print("PASS")
    }
}
