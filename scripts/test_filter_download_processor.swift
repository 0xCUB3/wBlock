import Foundation
import wBlockCoreService

final class FilterDownloadProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.requests.append(url)
        let body = "||included.example^\n"
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
struct FilterDownloadProcessorTests {
    static func main() async throws {
        let containerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-filter-processing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FilterDownloadProtocol.self]
        let session = URLSession(configuration: config)

        let sourceURL = URL(string: "https://fallback.example/lists/main.txt")!
        let filter = FilterList(
            name: "My Name",
            url: URL(string: "https://primary.example/main.txt")!,
            category: .custom,
            isCustom: true,
            description: "My Description",
            hasUserProvidedName: true,
            hasUserProvidedDescription: true
        )
        let raw = """
        ! Title: Remote Name
        ! Description: Remote Description
        ! Version: 2026.09.07
        ! Diff-Path: ../patches/latest.patch#main
        ! Diff-Name: main
        !#unsupported foo
        !#include child.txt
        ||parent.example^
        """

        let processed = try await FilterDownloadProcessor.processAndPublish(
            data: Data(raw.utf8),
            sourceURL: sourceURL,
            filter: filter,
            containerURL: containerURL,
            etag: "etag-1",
            lastModified: "Mon, 07 Sep 2026 20:00:00 GMT",
            urlSession: session
        )

        expectEqual(processed.filter.name, "My Name", "user-provided name must survive remote metadata")
        expectEqual(processed.filter.description, "My Description", "user-provided description must survive remote metadata")
        expectEqual(processed.filter.version, "2026.09.07", "remote version should update")
        expectEqual(processed.filter.sourceRuleCount, 2, "expanded source count should include included rules")
        expectEqual(processed.filter.rawSourceRuleCount, 1, "raw count should be measured before include expansion")
        expectEqual(processed.filter.etag, "etag-1", "etag should be reflected in processed metadata")
        expect(processed.strippedDirectives.contains("!#unsupported foo"), "unknown directives should be reported")
        expectEqual(
            FilterDownloadProtocol.requests.first?.absoluteString,
            "https://fallback.example/lists/child.txt",
            "relative includes must resolve from the actually served fallback URL"
        )

        let filename = ContentBlockerIncrementalCache.localFilename(for: filter)
        let publishedURL = containerURL.appendingPathComponent(filename)
        let published = try String(contentsOf: publishedURL, encoding: .utf8)
        expect(published.contains("||parent.example^"), "published source should include parent rule")
        expect(published.contains("||included.example^"), "published source should include resolved include")
        expect(!published.contains("!#unsupported"), "published source should strip unknown directives")

        let revisionStoreURL = containerURL.appendingPathComponent(PendingFilterUpdateRevisions.filename)
        let revision = PendingFilterUpdateRevisions.load(storeURL: revisionStoreURL)[filter.id.uuidString]
        expectEqual(revision?.etag, "etag-1", "publication should record the matching pending revision")

        let baselineURL = containerURL.appendingPathComponent("diff-baseline-\(filename)")
        expectEqual(
            try String(contentsOf: baselineURL, encoding: .utf8),
            raw,
            "delta baseline must preserve the exact preprocessed input body"
        )

        let noDiffRaw = "! Version: 2026.09.08\n||new.example^\n"
        let second = try await FilterDownloadProcessor.processAndPublish(
            data: Data(noDiffRaw.utf8),
            sourceURL: sourceURL,
            filter: processed.filter,
            containerURL: containerURL,
            etag: nil,
            lastModified: nil,
            urlSession: session
        )
        expectEqual(second.filter.description, "My Description", "metadata policy should remain identical on later publishes")
        expect(!FileManager.default.fileExists(atPath: baselineURL.path), "non-delta publish must clear stale delta baseline")
        let secondRevision = PendingFilterUpdateRevisions.load(storeURL: revisionStoreURL)[filter.id.uuidString]
        expect(secondRevision != nil, "second publish should leave a pending revision")
        expect(secondRevision?.etag == nil && secondRevision?.lastModified == nil, "nil validators must replace stale revision validators")

        let validSource = try Data(contentsOf: publishedURL)
        let validRevisions = PendingFilterUpdateRevisions.load(storeURL: revisionStoreURL)
        for invalid in [Data("<html>challenge</html>".utf8), Data([0xff, 0xfe])] {
            do {
                _ = try await FilterDownloadProcessor.processAndPublish(
                    data: invalid, sourceURL: sourceURL, filter: second.filter,
                    containerURL: containerURL, etag: "bad", lastModified: nil,
                    urlSession: session
                )
                fatalError("invalid response must not be published")
            } catch {
                expectEqual(try Data(contentsOf: publishedURL), validSource, "invalid response must preserve working rules")
                expectEqual(PendingFilterUpdateRevisions.load(storeURL: revisionStoreURL), validRevisions,
                            "invalid response must not advance the pending revision")
            }
        }

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FilterDownloadProcessor.processAndPublish(
                data: Data(noDiffRaw.utf8), sourceURL: sourceURL, filter: second.filter,
                containerURL: containerURL, etag: "cancelled", lastModified: nil,
                urlSession: session
            )
        }
        do {
            _ = try await cancelled.value
            fatalError("cancelled processing must not publish")
        } catch is CancellationError {
            expectEqual(try Data(contentsOf: publishedURL), validSource, "cancellation must preserve working rules")
            expectEqual(PendingFilterUpdateRevisions.load(storeURL: revisionStoreURL), validRevisions,
                        "cancellation must not advance the pending revision")
        }

        FilterDownloadProtocol.requests = []
        let optimized = FilterList(
            name: "Optimized",
            url: URL(string: "https://filters.example/list_optimized.txt")!,
            category: .ads
        )
        _ = try await FilterDownloadProcessor.processAndPublish(
            data: Data("!#include child.txt\n||optimized.example^\n".utf8),
            sourceURL: optimized.url,
            filter: optimized,
            containerURL: containerURL,
            etag: nil,
            lastModified: nil,
            urlSession: session
        )
        expect(FilterDownloadProtocol.requests.isEmpty, "optimized built-ins must bypass include preprocessing")

        print("PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fatalError("\(message). got \(String(describing: actual)), expected \(String(describing: expected))")
        }
    }
}
