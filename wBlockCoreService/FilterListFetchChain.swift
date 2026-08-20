import Foundation

public struct FilterListFetchResult: Sendable {
    public let data: Data
    public let response: HTTPURLResponse
    public let sourceURL: URL
    public let servedFallback: Bool

    public init(data: Data, response: HTTPURLResponse, sourceURL: URL, servedFallback: Bool) {
        self.data = data; self.response = response; self.sourceURL = sourceURL; self.servedFallback = servedFallback
    }
}

public enum FilterListFetchChain {
    public static func fetch(
        session: URLSession,
        primaryURL: URL,
        fallbackURLs: [URL],
        etag: String? = nil,
        lastModified: String? = nil,
        timeout: TimeInterval = 15,
        retryDelay: TimeInterval = 2
    ) async throws -> FilterListFetchResult {
        var lastError: Error = URLError(.badServerResponse)
        for attempt in 0..<2 {
            do {
                var request = NetworkRequestFactory.makeConditionalRequest(
                    url: primaryURL, etag: etag, lastModified: lastModified, timeout: timeout)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let result = try await session.data(for: request)
                guard let response = result.1 as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if response.statusCode == 304 { return FilterListFetchResult(data: result.0, response: response, sourceURL: primaryURL, servedFallback: false) }
                if response.statusCode == 200,
                   let content = String(data: result.0, encoding: .utf8),
                   FilterListContentValidator.appearsToBeFilterList(content) {
                    return FilterListFetchResult(data: result.0, response: response, sourceURL: primaryURL, servedFallback: false)
                }
                guard FilterUpdateResponseClassifier.isRetryable(statusCode: response.statusCode) || response.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                lastError = URLError(.badServerResponse)
            } catch { lastError = error }
            if attempt == 0 && retryDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }

        for fallback in fallbackURLs where fallback != primaryURL {
            do {
                var request = URLRequest(url: fallback, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
                request.httpShouldHandleCookies = false
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                // Fallback requests are unconditional, so a 304 is not usable.
                if http.statusCode == 200,
                   let content = String(data: data, encoding: .utf8),
                   FilterListContentValidator.appearsToBeFilterList(content) {
                    return FilterListFetchResult(data: data, response: http, sourceURL: fallback, servedFallback: true)
                }
                lastError = URLError(.badServerResponse)
            } catch { lastError = error }
        }
        throw lastError
    }
}
