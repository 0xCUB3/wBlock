//
//  FilterPreprocessor.swift
//  wBlockCoreService
//
//  Orchestrates the full preprocessing pipeline for a filter list:
//  1. Evaluate !#if / !#else / !#endif conditionals on the parent content.
//  2. Expand !#include directives via IncludeResolver.
//
//  This is the single entry point that Phase 4 will call before passing
//  content to SafariConverterLib.
//

import Foundation

/// Orchestrates conditional evaluation and include resolution for a filter list.
///
/// Usage:
/// ```swift
/// let preprocessor = FilterPreprocessor()
/// let expanded = await preprocessor.preprocess(content: rawContent, listURL: filterList.url)
/// // Pass `expanded` to SafariConverterLib
/// ```
///
/// Pipeline:
/// 1. `ConditionalEvaluator.evaluate(lines:)` — removes lines inside `!#if` blocks
///    that don't apply to the current platform. Running this first avoids wasted
///    network fetches for `!#include` lines inside excluded blocks.
/// 2. `IncludeResolver.expandIncludes(in:baseURL:visited:depth:)` — fetches sub-lists
///    and recursively expands nested includes (up to depth 5).
///
/// The returned string is ready for SafariConverterLib (`convertArray` or equivalent).
public actor FilterPreprocessor {

    private let resolver: IncludeResolver

    // MARK: - Initializer

    /// Creates a `FilterPreprocessor`.
    ///
    /// - Parameters:
    ///   - urlSession: Custom URLSession for testing. When `nil` (default),
    ///     `IncludeResolver` creates a session with a 15-second timeout.
    ///   - onFetchError: Optional closure invoked when a sub-list fetch fails. Forwarded to
    ///     `IncludeResolver`. Default `nil` preserves all existing call-sites unchanged (OBSV-01).
    public init(urlSession: URLSession? = nil, onFetchError: IncludeResolver.FetchErrorHandler? = nil) {
        self.resolver = IncludeResolver(urlSession: urlSession, onFetchError: onFetchError)
    }

    // MARK: - Public API

    /// Preprocesses raw filter list content, returning a fully expanded string.
    ///
    /// Steps:
    /// 1. Split `content` into lines.
    /// 2. Evaluate conditionals (`!#if` / `!#else` / `!#endif`) on the parent content.
    /// 3. Compute `baseURL` from `listURL.deletingLastPathComponent()` — the directory
    ///    that contains the filter list, used for resolving relative include paths.
    /// 4. Seed the visited set with `listURL` to prevent self-include cycles.
    /// 5. Expand all `!#include` directives recursively via `IncludeResolver`.
    /// 6. Join the expanded lines with `\n` and return.
    ///
    /// - Parameters:
    ///   - content: Raw filter list text (as downloaded from the network or disk).
    ///   - listURL: Full URL of the parent filter list (e.g. `https://example.com/list.txt`).
    ///             Used both as the origin for same-origin checks and as the self-cycle guard.
    /// - Returns: Fully expanded filter list content, ready for SafariConverterLib.
    public func preprocess(content: String, listURL: URL) async -> String {
        if Self.canPassThroughUnchanged(content) { return content }

        // Step 1: Split into lines
        let lines = content.components(separatedBy: .newlines)

        // Step 2: Evaluate conditionals on parent content FIRST.
        // This eliminates !#include lines inside excluded !#if blocks before any network
        // fetch — avoids wasted fetches (Research note: "evaluating first is better").
        let evaluated = ConditionalEvaluator.evaluate(lines: lines)

        // Step 3: Compute the base URL for relative path resolution.
        // CRITICAL: use deletingLastPathComponent(), NOT listURL itself.
        // If listURL is https://example.com/filters/list.txt, relative paths in the list
        // are resolved against https://example.com/filters/ — the parent directory.
        // (Research Pitfall 1)
        let baseURL = listURL.deletingLastPathComponent()

        // Step 4: Seed visited set with the parent URL to prevent A → A self-include.
        let visited: Set<String> = [IncludeResolver.visitKey(for: listURL)]

        // Step 5: Expand all !#include directives recursively.
        // Depth starts at 0; IncludeResolver increments on each level of recursion.
        let expanded = await resolver.expandIncludes(
            in: evaluated,
            baseURL: baseURL,
            visited: visited,
            depth: 0
        )

        // Step 6: Join and return as a single string for SafariConverterLib.
        return expanded.joined(separator: "\n")
    }

    /// A plain LF list within the expansion limits needs no line arrays.
    private static func canPassThroughUnchanged(_ content: String) -> Bool {
        guard content.utf8.count < IncludeResolver.maxExpandedBytes else { return false }
        var content = content
        return content.withUTF8 { bytes in
            var lineBreaks = 0
            var atLineStart = true
            for index in bytes.indices {
                let byte = bytes[index]
                if atLineStart {
                    if byte == 0x20 || byte == 0x09 { continue }
                    if byte >= 0x80 || ((byte == 0x21 || byte == 0x25) && hasDirective(in: bytes[index...])) {
                        return false
                    }
                    atLineStart = false
                }
                switch byte {
                case 0x0A:
                    lineBreaks += 1
                    if lineBreaks >= IncludeResolver.maxExpandedLines { return false }
                    atLineStart = true
                case 0x0B...0x0D:
                    return false
                case 0xC2 where index + 1 < bytes.count && bytes[index + 1] == 0x85:
                    return false
                case 0xE2 where index + 2 < bytes.count && bytes[index + 1] == 0x80:
                    if bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9 { return false }
                default:
                    break
                }
            }
            return true
        }
    }

    /// Conservatively leave directive parsing to the full preprocessor.
    private static func hasDirective(in bytes: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
        func startsWith(_ prefix: StaticString) -> Bool {
            bytes.starts(with: UnsafeBufferPointer(start: prefix.utf8Start, count: prefix.utf8CodeUnitCount))
        }
        switch bytes.first {
        case 0x21:
            if startsWith("!#if") {
                let after = bytes.startIndex + 4
                if after == bytes.endIndex { return true }
                let separator = bytes[after]
                return separator == 0x20 || separator == 0x09 || separator == 0x0A || separator >= 0x80
            }
            return startsWith("!#else") || startsWith("!#endif") || startsWith("!#include")
        case 0x25:
            return startsWith("%include ")
        default:
            return false
        }
    }
}
