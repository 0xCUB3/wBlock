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

/// One update run's uBO patch downloads. Every list in a uAssets release names
/// the same patch file, so each file is fetched once per run, not once per list.
public actor FilterPatchCache {
    private var downloads: [URL: Task<(Data, URLResponse), Error>] = [:]

    public init() {}

    func download(_ url: URL, session: URLSession, timeout: TimeInterval) async throws -> (Data, URLResponse) {
        if let download = downloads[url] { return try await download.value }
        let download = Task {
            try await session.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout))
        }
        downloads[url] = download
        return try await download.value
    }
}

public enum FilterListFetchChain {
    /// Raw copy of a list's last full download that advertised `! Diff-Path:`,
    /// which that list's next patch applies to.
    public static func diffBaselineURL(for filter: FilterList, containerURL: URL) -> URL {
        containerURL.appendingPathComponent("diff-baseline-\(ContentBlockerIncrementalCache.localFilename(for: filter))")
    }

    /// With `diffBaselineURL` and `patches`, a list that advertised
    /// `! Diff-Path:` is first brought up to date from its uBO patch. A patch
    /// that is not published yet means the list has not changed, reported as a
    /// 304. A patched list is reported as a 200 without validators, since the
    /// server's validators for the new body are unknown. Any patch failure
    /// falls through to the conditional GET.
    public static func fetch(
        session: URLSession,
        primaryURL: URL,
        fallbackURLs: [URL],
        etag: String? = nil,
        lastModified: String? = nil,
        timeout: TimeInterval = 15,
        retryDelay: TimeInterval = 2,
        diffBaselineURL: URL? = nil,
        patches: FilterPatchCache? = nil,
        log: (@Sendable (String) async -> Void)? = nil
    ) async throws -> FilterListFetchResult {
        if let diffBaselineURL, let patches,
           let delta = await patchedContent(
               listURL: primaryURL, baselineURL: diffBaselineURL, session: session,
               patches: patches, timeout: timeout, log: log ?? { _ in }) {
            let response = HTTPURLResponse(
                url: primaryURL, statusCode: delta == nil ? 304 : 200, httpVersion: nil, headerFields: nil)!
            return FilterListFetchResult(data: delta ?? Data(), response: response, sourceURL: primaryURL, servedFallback: false)
        }

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

    /// uBO-style delta update. `nil` means fall back to a full fetch,
    /// `.some(nil)` means no patch is due yet, and `.some(data)` is the patched list.
    private static func patchedContent(
        listURL: URL,
        baselineURL: URL,
        session: URLSession,
        patches: FilterPatchCache,
        timeout: TimeInterval,
        log: @Sendable (String) async -> Void
    ) async -> Data?? {
        guard let baselineText = try? String(contentsOf: baselineURL, encoding: .utf8),
              let metadata = FilterDiffUpdater.parseMetadata(from: baselineText)
        else { return nil }
        let now = Date()
        let availability = FilterDiffUpdater.patchAvailabilityTime(metadata: metadata, now: now)

        // uBO's "nopatch-yet" gate: the list and its patch ship together.
        if let availability, now < availability {
            await log("deferring patch fetch (expected at \(availability))")
            return .some(nil)
        }
        guard let patchURL = FilterDiffUpdater.resolvePatchURL(metadata: metadata, listURL: listURL) else { return nil }

        let patchText: String
        do {
            let (data, response) = try await patches.download(patchURL, session: session, timeout: timeout)
            guard let http = response as? HTTPURLResponse else { return nil }
            guard (200..<300).contains(http.statusCode) else {
                // Within the validity window a missing patch is "nopatch-yet";
                // beyond it, fall back to a full fetch.
                if let availability, metadata.diffExpiresSeconds > 0,
                   now.timeIntervalSince(availability) < 4 * metadata.diffExpiresSeconds {
                    await log("no patch yet (status \(http.statusCode)); deferring")
                    return .some(nil)
                }
                await log("patch fetch returned status \(http.statusCode); falling back to full fetch")
                return nil
            }
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            patchText = text
        } catch {
            await log("patch fetch failed (\(error.localizedDescription)); falling back to full fetch")
            return nil
        }

        guard let block = FilterDiffUpdater.parsePatchFile(patchText)?[metadata.diffName] else {
            await log("patch at \(patchURL.absoluteString) has no usable block '\(metadata.diffName)'; falling back to full fetch")
            return nil
        }
        switch FilterDiffUpdater.applyBlock(block, to: baselineText) {
        case .success(let patchedText):
            await log("applied \(patchText.utf8.count) byte patch from \(patchURL.absoluteString)")
            return .some(Data(patchedText.utf8))
        case .badPatch:
            await log("patch failed to apply (malformed); falling back to full fetch")
            return nil
        case .checksumMismatch(let expected, let computed):
            await log("checksum mismatch (expected \(expected), computed \(computed)); falling back to full fetch")
            return nil
        }
    }
}
