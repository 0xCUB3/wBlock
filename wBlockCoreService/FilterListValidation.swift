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
    /// Key under which two list URLs count as the same list. Scheme, host
    /// case, a default port and a trailing slash do not make a different list,
    /// so http and https variants of one address are duplicates (#681).
    public static func identityKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.scheme = nil
        components.host = components.host?.lowercased()
        if components.port == 80 || components.port == 443 {
            components.port = nil
        }
        components.fragment = nil
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path
        return components.string ?? url.absoluteString.lowercased()
    }

    public static func isSameList(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs == rhs || identityKey(for: lhs) == identityKey(for: rhs)
    }

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
        let pasted = looksLikePaste(from: oldValue, to: newValue)
        let normalized = normalizeURLInput(rejoiningPastedLines(from: oldValue, to: newValue), rejoinWrappedLines: false)
        // A typed Return keeps its newline so the next URL can follow; a
        // paste's trailing blank lines are noise.
        return pasted ? normalized.trimmingCharacters(in: .newlines) : normalized
    }

    public static func normalizeSingleURLInput(from oldValue: String, to newValue: String) -> String {
        normalizeSingleURLInput(rejoiningPastedLines(from: oldValue, to: newValue), rejoinWrappedLines: false)
    }

    /// Rejoins a wrapped URL only inside the text a paste inserted (#772).
    /// Typing, deleting, or fixing a line elsewhere leaves the other lines
    /// alone, and a line that is already a complete URL never absorbs the
    /// line below it.
    static func rejoiningPastedLines(from oldValue: String, to newValue: String) -> String {
        guard let insertion = insertedText(from: oldValue, to: newValue),
              looksLikePaste(insertion.text) else {
            return newValue
        }
        let leading = String(insertion.text.prefix(while: \.isNewline))
        let trailing = String(insertion.text.reversed().prefix(while: \.isNewline))
        let joined = leading + normalizeURLInput(insertion.text, rejoinWrappedLines: true) + trailing
        let characters = Array(newValue)
        let prefix = String(characters[..<insertion.start])
        let suffix = String(characters[(insertion.start + insertion.text.count)...])
        return prefix + joined + suffix
    }

    public static func looksLikePaste(from oldValue: String, to newValue: String) -> Bool {
        guard let insertion = insertedText(from: oldValue, to: newValue) else { return false }
        return looksLikePaste(insertion.text)
    }

    /// Key presses insert one character, or a couple when the system
    /// coalesces fast typing. A pasted URL is far longer, and a paste that
    /// needs rejoining carries text on both sides of a newline.
    private static func looksLikePaste(_ inserted: String) -> Bool {
        let trimmed = inserted.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains(where: \.isNewline) || trimmed.count >= 6
    }

    /// The characters a pure insertion added, or nil for a deletion or a
    /// replacement.
    private static func insertedText(from oldValue: String, to newValue: String) -> (start: Int, text: String)? {
        let old = Array(oldValue)
        let new = Array(newValue)
        guard new.count > old.count else { return nil }
        var prefix = 0
        while prefix < old.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        guard prefix + suffix == old.count else { return nil }
        return (prefix, String(new[prefix..<(new.count - suffix)]))
    }

    public static func normalizeSingleURLInput(_ rawValue: String, rejoinWrappedLines: Bool = true) -> String {
        let normalized = normalizeURLInput(rawValue, rejoinWrappedLines: rejoinWrappedLines)
        return normalized.components(separatedBy: .newlines).first ?? ""
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
               !isCompleteURLLine(last),
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
        return candidate.hasPrefix("http://") || candidate.hasPrefix("https://") || candidate.hasPrefix("www.")
    }

    /// A URL whose last path component names a file is already whole, so the
    /// line under it is a new entry rather than a wrapped tail (#772).
    private static func isCompleteURLLine(_ line: String) -> Bool {
        guard let url = validatedRemoteURL(from: unwrappedURLLine(line)) else { return false }
        let leaf = url.lastPathComponent
        return leaf != "/" && leaf.contains(".")
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
