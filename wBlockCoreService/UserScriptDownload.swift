import Foundation

/// Keeps mirror transport separate from subscription identity and header update URLs.
enum UserScriptDownload {
    struct Content {
        let text: String
        let response: URLResponse
        let sourceURL: URL
    }

    static func fallbackURLs(for primary: URL) -> [URL] {
        guard BuiltInUserScripts.protectedURLs.contains(primary.absoluteString),
              primary.host == "raw.githubusercontent.com",
              primary.path.hasPrefix("/ryanbr/TwitchAdSolutions/")
                || primary.path.hasPrefix("/0xCUB3/wBlock-userscripts/")
        else { return [] }
        return FilterListURLMirror.fallbackURLs(for: primary).filter {
            $0.scheme == "https" && $0.host == "cdn.jsdelivr.net"
                && UserScriptURLSupport.validatedRemoteURL(from: $0.absoluteString) == $0
        }
    }

    /// The caller supplies the existing HTTP/status/size-bounded transport.
    @MainActor
    static func fetch(
        from primary: URL,
        load: (URL) async throws -> (Data, URLResponse)
    ) async throws -> Content {
        let mirrors = fallbackURLs(for: primary)
        var lastError: Error = URLError(.resourceUnavailable)
        for endpoint in [primary] + mirrors {
            try Task.checkCancellation()
            do {
                let (data, response) = try await load(endpoint)
                try Task.checkCancellation()
                let text = try UserScriptContentValidation.downloadedSource(from: data)
                if !mirrors.isEmpty {
                    // Reject error documents and redirected sources before any source/metadata cache writes.
                    guard response.url == endpoint, response.mimeType?.lowercased() != "text/html",
                          UserScript.containsUserScriptMetadataBlock(text)
                    else { throw URLError(.cannotParseResponse) }
                }
                return Content(text: text, response: response, sourceURL: endpoint)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                lastError = error
            }
        }
        throw lastError
    }
}
