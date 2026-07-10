//
//  IncludeResolver.swift
//  wBlockCoreService
//
//  Fetches and recursively expands !#include directives in filter list content.
//
//  Algorithm derived from AdGuard FiltersDownloader resolveInclude + validateUrl
//  (https://github.com/AdguardTeam/FiltersDownloader).
//
//  Key behaviors:
//  - Same-origin restriction: cross-origin includes return [] (PREP-03)
//  - Cycle detection: visited-URL Set<String> passed by value (PREP-04)
//  - Depth limit: maxDepth = 5; deeper chains return [] (PREP-04)
//  - Sub-list conditionals: ConditionalEvaluator.evaluate() runs before recursion (Pitfall 2)
//  - Failure policy: all error paths return [] — degraded-continue, never throw (Phase 5 SC3)
//

import Foundation

/// Fetches sub-list content for `!#include` directives and recursively expands them.
///
/// Each include line is resolved relative to the base URL of the containing file.
/// Safety guards:
/// - **Same-origin**: the sub-list URL must share scheme, host, and port with the base URL.
/// - **Cycle detection**: normalized (lowercased) absolute URL strings are tracked in a `Set<String>`
///   passed by value; re-visiting a URL in the same chain returns `[]`.
/// - **Depth limit**: chains deeper than `maxDepth` (5) are truncated and return `[]`.
///
/// All error paths (URL construction failure, cross-origin, cycle, HTTP error, decode error)
/// return an empty array — the caller's other lines are preserved (degraded-continue policy).
public actor IncludeResolver {

    /// Called when a sub-list fetch fails. Parameters: the sub-list URL that failed, and the
    /// HTTP status code (`nil` for network errors like timeout or DNS failure).
    public typealias FetchErrorHandler = @Sendable (URL, Int?) async -> Void

    private let urlSession: URLSession
    private let onFetchError: FetchErrorHandler?

    /// Maximum recursion depth for nested `!#include` directives (PREP-04).
    public static let maxDepth = 5
    public static let maxIncludedFileBytes = 10 * 1024 * 1024
    public static let maxExpandedLines = 500_000
    public static let maxExpandedBytes = 50 * 1024 * 1024

    private struct ExpansionResult {
        let lines: [String]
        let bytes: Int
    }

    // MARK: - Initializer

    /// Creates an `IncludeResolver`.
    ///
    /// - Parameters:
    ///   - urlSession: Custom session for testing. When `nil` (default), a session
    ///     with a 15-second request timeout is created — shorter than the parent list's 30s
    ///     timeout to prevent timeout stacking across 5 recursion levels (Research Pitfall 4).
    ///   - onFetchError: Optional closure invoked when a sub-list fetch fails (HTTP error or
    ///     network error). Receives the failed URL and the HTTP status code (nil for network errors).
    ///     Default `nil` preserves all existing call-sites unchanged (OBSV-01).
    public init(urlSession: URLSession? = nil, onFetchError: FetchErrorHandler? = nil) {
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 60
            self.urlSession = URLSession(configuration: config)
        }
        self.onFetchError = onFetchError
    }

    // MARK: - Public API

    /// Expands all `!#include` lines found in `lines`, returning the fully expanded result.
    ///
    /// Non-include lines are appended verbatim. This is the primary entry point for
    /// `FilterPreprocessor` (plan 02).
    ///
    /// - Parameters:
    ///   - lines: Lines from the parent filter list (after `ConditionalEvaluator.evaluate`).
    ///   - baseURL: URL of the directory that contains the parent filter list.
    ///   - visited: Normalized URLs already in the current include chain (cycle guard).
    ///   - depth: Current recursion depth (0-based; 0 means called from the top-level list).
    /// - Returns: Lines with all `!#include` directives replaced by their expanded content.
    public func expandIncludes(
        in lines: [String],
        baseURL: URL,
        visited: Set<String>,
        depth: Int
    ) async -> [String] {
        await expandIncludes(
            in: lines,
            baseURL: baseURL,
            visited: visited,
            depth: depth,
            maximumLines: Self.maxExpandedLines,
            maximumBytes: Self.maxExpandedBytes
        ).lines
    }

    /// Resolves a single `!#include` line into the expanded lines from the referenced sub-list.
    ///
    /// Returns `[]` on any failure — same-origin violation, cycle, depth exceeded, network
    /// error, or decode error (degraded-continue policy).
    ///
    /// - Parameters:
    ///   - includeLine: The raw `!#include path/to/sub.txt` line (already trimmed).
    ///   - baseURL: URL of the directory containing the file with this include line.
    ///   - visited: Normalized (lowercased absolute) URL strings already in the chain.
    ///   - depth: Current recursion depth (guard against > `maxDepth`).
    /// - Returns: Expanded lines from the sub-list, or `[]` on any failure.
    public func resolve(
        includeLine: String,
        baseURL: URL,
        visited: Set<String>,
        depth: Int
    ) async -> [String] {
        await resolve(
            includeLine: includeLine,
            baseURL: baseURL,
            visited: visited,
            depth: depth,
            maximumLines: Self.maxExpandedLines,
            maximumBytes: Self.maxExpandedBytes
        ).lines
    }

    private func expandIncludes(
        in lines: [String],
        baseURL: URL,
        visited: Set<String>,
        depth: Int,
        maximumLines: Int,
        maximumBytes: Int
    ) async -> ExpansionResult {
        var result: [String] = []
        result.reserveCapacity(min(lines.count, maximumLines))
        var resultBytes = 0

        for line in lines {
            guard result.count < maximumLines, resultBytes < maximumBytes else { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("!#include") {
                let expanded = await resolve(
                    includeLine: trimmed,
                    baseURL: baseURL,
                    visited: visited,
                    depth: depth,
                    maximumLines: maximumLines - result.count,
                    maximumBytes: maximumBytes - resultBytes
                )
                result.append(contentsOf: expanded.lines)
                resultBytes += expanded.bytes
            } else {
                let lineBytes = line.utf8.count + 1
                guard resultBytes + lineBytes <= maximumBytes else { break }
                result.append(line)
                resultBytes += lineBytes
            }
        }
        return ExpansionResult(lines: result, bytes: resultBytes)
    }

    private func resolve(
        includeLine: String,
        baseURL: URL,
        visited: Set<String>,
        depth: Int,
        maximumLines: Int,
        maximumBytes: Int
    ) async -> ExpansionResult {
        guard depth < Self.maxDepth, maximumLines > 0, maximumBytes > 0 else {
            return ExpansionResult(lines: [], bytes: 0)
        }

        let rawPath = String(includeLine.dropFirst("!#include".count))
            .trimmingCharacters(in: .whitespaces)
        guard !rawPath.isEmpty,
              let subURL = URL(string: rawPath, relativeTo: baseURL)?.absoluteURL,
              isSameOrigin(subURL, as: baseURL) else {
            return ExpansionResult(lines: [], bytes: 0)
        }

        let normalizedKey = subURL.absoluteString.lowercased()
        guard !visited.contains(normalizedKey) else {
            return ExpansionResult(lines: [], bytes: 0)
        }
        var nextVisited = visited
        nextVisited.insert(normalizedKey)

        do {
            let (downloadURL, response) = try await urlSession.download(from: subURL)
            defer { try? FileManager.default.removeItem(at: downloadURL) }

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await onFetchError?(subURL, (response as? HTTPURLResponse)?.statusCode)
                return ExpansionResult(lines: [], bytes: 0)
            }
            let expectedBytes = response.expectedContentLength
            guard expectedBytes <= 0 || expectedBytes <= Self.maxIncludedFileBytes else {
                await onFetchError?(subURL, http.statusCode)
                return ExpansionResult(lines: [], bytes: 0)
            }
            let fileSize = try downloadURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= Self.maxIncludedFileBytes else {
                await onFetchError?(subURL, http.statusCode)
                return ExpansionResult(lines: [], bytes: 0)
            }
            let content = try String(contentsOf: downloadURL, encoding: .utf8)

            let evaluated = ConditionalEvaluator.evaluate(
                lines: content.components(separatedBy: .newlines)
            )
            return await expandIncludes(
                in: evaluated,
                baseURL: subURL.deletingLastPathComponent(),
                visited: nextVisited,
                depth: depth + 1,
                maximumLines: maximumLines,
                maximumBytes: maximumBytes
            )
        } catch {
            await onFetchError?(subURL, nil)
            return ExpansionResult(lines: [], bytes: 0)
        }
    }

    // MARK: - Private helpers

    /// Returns `true` when `url` and `base` share the same origin (scheme + host + port).
    ///
    /// Nil host == nil host is treated as same-origin (covers the `file://` edge case).
    /// Port optionals are compared directly: a nil port (scheme default) equals another nil port.
    private func isSameOrigin(_ url: URL, as base: URL) -> Bool {
        // Scheme must be present and equal (case-insensitive)
        guard let urlScheme = url.scheme?.lowercased(),
              let baseScheme = base.scheme?.lowercased(),
              urlScheme == baseScheme else {
            return false
        }

        // Host comparison (lowercased); nil == nil is same-origin
        let urlHost = url.host?.lowercased()
        let baseHost = base.host?.lowercased()
        guard urlHost == baseHost else {
            return false
        }

        // Port comparison; nil means the default port for the scheme
        guard url.port == base.port else {
            return false
        }

        return true
    }
}
