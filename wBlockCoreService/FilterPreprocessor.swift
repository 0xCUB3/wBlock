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
    /// - Parameter urlSession: Custom URLSession for testing. When `nil` (default),
    ///   `IncludeResolver` creates a session with a 15-second timeout.
    public init(urlSession: URLSession? = nil) {
        self.resolver = IncludeResolver(urlSession: urlSession)
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
        // Normalized to lowercase for reliable equality matching (same as IncludeResolver).
        let visited: Set<String> = [listURL.absoluteString.lowercased()]

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
}
