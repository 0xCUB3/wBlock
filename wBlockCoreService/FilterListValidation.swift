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
            let candidate = unwrappedURLLine(line)
            guard !candidate.isEmpty else { continue }

            guard let url = validatedRemoteURL(from: candidate) else {
                invalidLineNumbers.append(index + 1)
                continue
            }

            guard seenURLs.insert(url).inserted else { continue }
            urls.append(url)
        }

        return FilterListURLParseResult(urls: urls, invalidLineNumbers: invalidLineNumbers)
    }

    /// Cleans URL-field text so a paste cannot hide the link behind extra blank
    /// lines. Bulk entry still works: a single trailing newline is kept while
    /// typing so the next URL can be added.
    public static func normalizeURLInput(from oldValue: String, to newValue: String) -> String {
        normalizeURLInput(newValue, rejoinWrappedLines: looksLikePaste(from: oldValue, to: newValue))
    }

    public static func normalizeURLInput(_ rawValue: String, rejoinWrappedLines: Bool) -> String {
        let hadTrailingNewline = rawValue.last?.isNewline ?? false
        var lines: [String] = []

        for line in rawValue.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if rejoinWrappedLines,
               let last = lines.last,
               isURLLineStart(last),
               !isURLLineStart(trimmed) {
                lines[lines.count - 1] = last + trimmed
            } else {
                lines.append(trimmed)
            }
        }

        var result = lines.joined(separator: "\n")
        if hadTrailingNewline && !rejoinWrappedLines && !result.isEmpty {
            result += "\n"
        }
        return result
    }

    public static func looksLikePaste(from oldValue: String, to newValue: String) -> Bool {
        if newValue == oldValue { return false }
        if newValue.hasPrefix(oldValue) || oldValue.hasPrefix(newValue) {
            return abs(newValue.count - oldValue.count) > 1
        }
        return newValue.count > 1
    }

    private static func hasDisallowedScriptExtension(in path: String) -> Bool {
        let lowercased = path.lowercased()
        return lowercased.hasSuffix(".user.js")
            || lowercased.hasSuffix(".js")
            || lowercased.hasSuffix(".mjs")
            || lowercased.hasSuffix(".cjs")
    }

    private static func unwrappedURLLine(_ line: String) -> String {
        var candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = candidate.first, let last = candidate.last,
           (first == "<" && last == ">")
            || (first == "\"" && last == "\"")
            || (first == "'" && last == "'") {
            candidate = String(candidate.dropFirst().dropLast())
        }
        return candidate
    }

    private static func isURLLineStart(_ line: String) -> Bool {
        let candidate = unwrappedURLLine(line).lowercased()
        return candidate.hasPrefix("http://") || candidate.hasPrefix("https://")
    }
}

public enum FilterListContentValidator {
    public static let supportedLocalFileExtensions: Set<String> = ["txt", "list"]

    public static func isSupportedLocalFile(_ url: URL) -> Bool {
        supportedLocalFileExtensions.contains(url.pathExtension.lowercased())
    }

    public static func appearsToBeFilterList(_ content: String) -> Bool {
        // Fast-path: reject HTML challenge/protection pages.
        let prefix = String(content.prefix(2048))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html") {
            return false
        }

        // A metadata block is unambiguously a userscript, even when its body also
        // contains text that resembles an ad-block rule.
        if containsUserScriptMetadataBlock(content) {
            return false
        }

        // Validate line-by-line. Hostnames are deliberately not treated as JS
        // merely because they contain `window.` or `document.`: both are valid
        // filter hosts and may occur in network, option, or cosmetic rules.
        var scannedLines = 0
        var sawFilterSyntax = false
        for line in content.components(separatedBy: .newlines) {
            guard scannedLines < 100 else { break }
            scannedLines += 1

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // A valid ABP host/network rule wins before keyword checks. Hostnames such
            // as `return.example.com` and `class.example.com` are not JavaScript.
            if isFilterSyntaxLine(trimmed) {
                sawFilterSyntax = true
                continue
            }
            if isExplicitJavaScriptLine(trimmed) { return false }
        }

        return sawFilterSyntax
    }

    private static func isFilterSyntaxLine(_ line: String) -> Bool {
        if line.hasPrefix("!") { return true } // ABP comment/directive
        if line.contains("##") || line.contains("#@#")
            || line.contains("#?#") || line.contains("#@?#")
            || line.contains("#$#") || line.contains("#@$#")
            || line.contains("#$?#") || line.contains("#@$?#")
            || line.contains("#%#") || line.contains("#@%#") {
            return true
        }
        if line.hasPrefix("@@") || line.hasPrefix("||") || line.hasPrefix("|") {
            return true
        }
        if line.range(of: #"\$[A-Za-z][A-Za-z0-9_-]*(?:=|,|$)"#, options: .regularExpression) != nil {
            return true
        }

        // ABP also accepts host-only rules. Keep this intentionally narrow so a
        // paragraph of prose does not become a valid filter list.
        return line.range(
            of: #"^(?:\*|localhost|(?:[A-Za-z0-9](?:[A-Za-z0-9_-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,})(?:[/:^*?].*)?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isExplicitJavaScriptLine(_ line: String) -> Bool {
        let patterns = [
            #"^\s*(?:const|let|var)\s+[A-Za-z_$][A-Za-z0-9_$]*\s*="#,
            #"^\s*(?:async\s+)?function\s+[A-Za-z_$][A-Za-z0-9_$]*\s*\("#,
            #"^\s*(?:if|for|while|switch|try|catch|return|throw|class|import|export)\b"#,
            #"^\s*(?:console|window|document)\s*\.\s*[A-Za-z_$][A-Za-z0-9_$]*\s*(?:\(|=|;|\+\+|--)"#,
            #"^\s*<script\b"#,
            #"=>\s*[\{(]"#,
            #"^\s*javascript:"#
        ]
        return patterns.contains { line.range(of: $0, options: .regularExpression) != nil }
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
