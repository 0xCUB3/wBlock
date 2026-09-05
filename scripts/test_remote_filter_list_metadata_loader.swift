import Foundation

final class MetadataProtocol: URLProtocol {
    enum Mode {
        case partial
        case ignoredRange
        case notFound
        case neverFinishes
    }

    private static let stateLock = NSLock()
    private static var storedMode: Mode = .partial
    private static var storedRange: String?
    private static var storedStopped = false
    private static var storedBytes = 0
    private let streamLock = NSLock()
    private var streamStopped = false

    static var mode: Mode {
        get { stateLock.withLock { storedMode } }
        set { stateLock.withLock { storedMode = newValue } }
    }
    static var requestedRange: String? {
        get { stateLock.withLock { storedRange } }
        set { stateLock.withLock { storedRange = newValue } }
    }
    static var stoppedLoading: Bool {
        get { stateLock.withLock { storedStopped } }
        set { stateLock.withLock { storedStopped = newValue } }
    }
    static var bytesSent: Int {
        get { stateLock.withLock { storedBytes } }
        set { stateLock.withLock { storedBytes = newValue } }
    }

    static let metadataPrefix = """
    ! Title: Remote Test List
    ! Description: Metadata from the first lines
    """

    static let ignoredRangeContent = metadataPrefix + "\n" + String(repeating: "||example.com^\n", count: 2_000)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static func reset(mode: Mode) {
        Self.mode = mode
        requestedRange = nil
        stoppedLoading = false
        bytesSent = 0
    }

    override func startLoading() {
        Self.requestedRange = request.value(forHTTPHeaderField: "Range")
        switch Self.mode {
        case .partial:
            send(statusCode: 206, body: Self.metadataPrefix + "\n||example.com^\n")
        case .ignoredRange:
            sendIgnoredRangeStream()
        case .notFound:
            send(statusCode: 404, body: Self.metadataPrefix)
        case .neverFinishes:
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/plain; charset=utf-8"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
    }

    override func stopLoading() {
        streamLock.withLock { streamStopped = true }
        Self.stoppedLoading = true
    }

    private func send(statusCode: Int, body: String) {
        let data = body.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        Self.bytesSent += data.count
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func sendIgnoredRangeStream(offset: Int = 0) {
        if streamLock.withLock({ streamStopped }) { return }
        if offset == 0 {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/plain; charset=utf-8"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        let data = Self.ignoredRangeContent.data(using: .utf8)!
        guard offset < data.count else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let chunkSize = 16
        let end = min(offset + chunkSize, data.count)
        let chunk = data.subdata(in: offset..<end)
        Self.bytesSent += chunk.count
        client?.urlProtocol(self, didLoad: chunk)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) { [weak self] in
            self?.sendIgnoredRangeStream(offset: end)
        }
    }
}

@main
struct RemoteFilterListMetadataLoaderTests {
    static func main() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MetadataProtocol.self]
        let session = URLSession(configuration: config)

        await testPartialResponse(session: session)
        await testIgnoredRangeIsCancelledAfterBound(session: session)
        await testNonSuccessResponse(session: session)
        await testCancellation(session: session)
        print("PASS")
    }

    private static func testPartialResponse(session: URLSession) async {
        MetadataProtocol.reset(mode: .partial)
        do {
            let metadata = try await RemoteFilterListMetadataLoader.fetch(
                from: URL(string: "https://example.com/filter.txt")!,
                session: session,
                maxBytes: 128,
                maxLines: 5
            )
            expectEqual(metadata.title, "Remote Test List", "expected title metadata to be parsed")
            expectEqual(metadata.description, "Metadata from the first lines", "expected description metadata to be parsed")
            expectEqual(MetadataProtocol.requestedRange, "bytes=0-127", "expected metadata fetch to request a byte range")
        } catch {
            fail("unexpected metadata fetch error: \(error)")
        }
    }

    private static func testIgnoredRangeIsCancelledAfterBound(session: URLSession) async {
        MetadataProtocol.reset(mode: .ignoredRange)
        do {
            let metadata = try await RemoteFilterListMetadataLoader.fetch(
                from: URL(string: "https://example.com/ignores-range.txt")!,
                session: session,
                maxBytes: 96,
                maxLines: 3
            )
            expectEqual(metadata.title, "Remote Test List", "expected title from server that ignored Range")
            expectEqual(metadata.description, "Metadata from the first lines", "expected description from server that ignored Range")
            await waitUntil("expected ignored Range stream to be cancelled") { MetadataProtocol.stoppedLoading }
            expect(MetadataProtocol.bytesSent < MetadataProtocol.ignoredRangeContent.utf8.count, "expected loader not to download entire ignored Range response")
        } catch {
            fail("unexpected ignored Range metadata error: \(error)")
        }
    }

    private static func testNonSuccessResponse(session: URLSession) async {
        MetadataProtocol.reset(mode: .notFound)
        do {
            let metadata = try await RemoteFilterListMetadataLoader.fetch(
                from: URL(string: "https://example.com/not-found.txt")!,
                session: session,
                maxBytes: 128,
                maxLines: 5
            )
            expectEqual(metadata.title, nil, "expected title to be nil for non-2xx response")
            expectEqual(metadata.description, nil, "expected description to be nil for non-2xx response")
        } catch {
            fail("non-2xx response should not throw: \(error)")
        }
    }

    private static func testCancellation(session: URLSession) async {
        MetadataProtocol.reset(mode: .neverFinishes)
        let task = Task {
            try await RemoteFilterListMetadataLoader.fetch(
                from: URL(string: "https://example.com/hangs.txt")!,
                session: session,
                maxBytes: 128,
                maxLines: 5
            )
        }
        await waitUntil("expected request to start before cancellation") { MetadataProtocol.requestedRange != nil }
        task.cancel()
        do {
            _ = try await task.value
            fail("expected cancelled metadata fetch to throw")
        } catch {
            expect(error is CancellationError || (error as? URLError)?.code == .cancelled, "expected cancellation error")
            await waitUntil("expected cancellation to stop URL loading") { MetadataProtocol.stoppedLoading }
        }
    }

    private static func waitUntil(_ message: String, condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        fail(message)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fail("\(message). got \(String(describing: actual)), expected \(String(describing: expected))")
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
