//
//  FilterListValidation.swift
//  wBlock
//

import Foundation

public struct FilterListURLParseResult: Equatable {
    public let urls: [URL]
    public let invalidLineNumbers: [Int]

    public init(urls: [URL], invalidLineNumbers: [Int]) {
        self.urls = urls
        self.invalidLineNumbers = invalidLineNumbers
    }
}

public enum FilterListURLSupport {
    public static func validatedRemoteURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              !hasDisallowedScriptExtension(in: components.path),
              let url = components.url else {
            return nil
        }

        return url
    }

    /// Parses filter list URLs pasted one per line.
    /// Valid URLs are returned once, preserving their input order.
    public static func parseRemoteURLs(from rawValue: String) -> FilterListURLParseResult {
        var seenURLs = Set<URL>()
        var urls: [URL] = []
        var invalidLineNumbers: [Int] = []

        for (index, line) in rawValue.components(separatedBy: "\n").enumerated() {
            var candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }

            if let first = candidate.first, let last = candidate.last,
               (first == "<" && last == ">")
                || (first == "\"" && last == "\"")
                || (first == "'" && last == "'") {
                candidate = String(candidate.dropFirst().dropLast())
            }

            guard let url = validatedRemoteURL(from: candidate) else {
                invalidLineNumbers.append(index + 1)
                continue
            }

            guard seenURLs.insert(url).inserted else { continue }
            urls.append(url)
        }

        return FilterListURLParseResult(urls: urls, invalidLineNumbers: invalidLineNumbers)
    }

    private static func hasDisallowedScriptExtension(in path: String) -> Bool {
        let lowercased = path.lowercased()
        return lowercased.hasSuffix(".user.js")
            || lowercased.hasSuffix(".js")
            || lowercased.hasSuffix(".mjs")
            || lowercased.hasSuffix(".cjs")
    }
}

public enum FilterListContentValidator {
    public static func appearsToBeFilterList(_ content: String) -> Bool {
        // Fast-path: reject HTML challenge/protection pages.
        let prefix = String(content.prefix(2048))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html") {
            return false
        }

        // Userscripts can look text-like enough to pass a permissive filter check.
        // Reject Greasemonkey/Tampermonkey metadata blocks before counting lines.
        if containsUserScriptMetadataBlock(content) {
            return false
        }

        // A filter list must have at least one meaningful non-empty line in the first 100 lines.
        // Meaningful = not empty, not a [header] bracket line.
        // Comments (!), directives (!#include, !#if, etc.), and actual rules all count as meaningful.
        var scannedLines = 0
        var meaningfulLineCount = 0

        content.enumerateLines { line, stop in
            if scannedLines >= 100 { stop = true; return }
            scannedLines += 1

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("[") {
                meaningfulLineCount += 1
            }
            if meaningfulLineCount >= 1 { stop = true }
        }

        return meaningfulLineCount >= 1
    }

    private static func containsUserScriptMetadataBlock(_ content: String) -> Bool {
        var scannedLines = 0
        var sawStart = false

        content.enumerateLines { line, stop in
            if scannedLines >= 100 { stop = true; return }
            scannedLines += 1

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "// ==UserScript==" {
                sawStart = true
                return
            }

            if sawStart && trimmed == "// ==/UserScript==" {
                stop = true
            }
        }

        return sawStart
    }
}
