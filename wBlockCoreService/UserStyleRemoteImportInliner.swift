//
//  UserStyleRemoteImportInliner.swift
//  wBlockCoreService
//
//  Resolves remote Less `@import` statements when userstyle source enters the
//  app (URL add, download, update, and editor save). The bounded offline
//  compiler host has no network access by design and keeps processImports
//  disabled, so imported libraries are fetched once here and inlined into the
//  stored source. Every later compile — hydration, sidecar validation, and
//  cloud-synced devices — then works offline from self-contained source.
//
//  Only unambiguous Less imports are inlined: an absolute http(s) URL whose
//  path ends in .less (or an explicit (less) option), with no media query and
//  no import options beyond (less)/(once). Plain CSS imports and anything
//  uncertain are preserved untouched, matching the compiler contract that
//  ordinary CSS imports pass through unresolved.
//

import Foundation

public enum UserStyleRemoteImportInliner {

    public static let maximumImportDepth = 4

    public struct InlineError: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }

        static func fetchFailed(_ url: String) -> InlineError {
            InlineError(message: String(localized: "Couldn't download the imported style \"%@\".", comment: "Userstyle remote import download error").replacingOccurrences(of: "%@", with: url))
        }
        static var nestedTooDeeply: InlineError {
            InlineError(message: String(localized: "Style imports nest too deeply.", comment: "Userstyle remote import depth error"))
        }
        static var tooLarge: InlineError {
            InlineError(message: String(localized: "Userstyle source exceeds the 2 MiB limit.", comment: "Userstyle compiler source size error"))
        }
    }

    /// True when the content is a Less userstyle carrying at least one
    /// inlineable remote import. Cheap gate for ingestion paths.
    public static func containsRemoteLessImports(in content: String) -> Bool {
        guard isLessUserStyle(content) else { return false }
        return !inlineableImports(in: content).isEmpty
    }

    /// Returns the content with every inlineable remote Less import replaced by
    /// its fetched source, recursively and bounded. Non-Less styles and styles
    /// without remote imports are returned unchanged. Fetch failures throw.
    public static func inliningRemoteImports(
        in content: String,
        fetch: (URL) async throws -> String
    ) async throws -> String {
        guard isLessUserStyle(content) else { return content }
        var visited = Set<String>()
        return try await inline(content, depth: maximumImportDepth, visited: &visited, fetch: fetch)
    }

    private static func isLessUserStyle(_ content: String) -> Bool {
        guard UserStyleSupport.isUserStyleContent(content),
              let metadata = UserStyleSupport.parsed(from: content, compiledBody: nil, compileSource: false)
        else { return false }
        return UserStylePreprocessorService.normalize(metadata.preprocessor) == "less"
    }

    private static func inline(
        _ content: String,
        depth: Int,
        visited: inout Set<String>,
        fetch: (URL) async throws -> String
    ) async throws -> String {
        let imports = inlineableImports(in: content)
        guard !imports.isEmpty else { return content }
        guard depth > 0 else { throw InlineError.nestedTooDeeply }

        let bytes = Array(content.utf8)
        var pieces: [String] = []
        var cursor = 0
        for statement in imports {
            pieces.append(String(decoding: bytes[cursor..<statement.range.lowerBound], as: UTF8.self))
            cursor = statement.range.upperBound
            if visited.contains(statement.url) {
                // Matches Less import-once semantics: repeated imports vanish.
                continue
            }
            visited.insert(statement.url)
            guard let url = URL(string: statement.url) else {
                throw InlineError.fetchFailed(statement.url)
            }
            let fetched: String
            do {
                fetched = try await fetch(url)
            } catch {
                throw InlineError.fetchFailed(statement.url)
            }
            let resolved = try await inline(fetched, depth: depth - 1, visited: &visited, fetch: fetch)
            pieces.append("/* wBlock inlined @import \"\(statement.url)\" */\n")
            pieces.append(resolved)
        }
        pieces.append(String(decoding: bytes[cursor..<bytes.count], as: UTF8.self))
        let result = pieces.joined()
        guard result.utf8.count <= UserStylePreprocessorService.maximumSourceBytes else {
            throw InlineError.tooLarge
        }
        return result
    }

    // MARK: - Statement scanning

    struct ImportStatement {
        /// Byte range of the whole `@import ... ;` statement in the content's UTF-8.
        let range: Range<Int>
        let url: String
    }

    /// Scans for `@import` statements outside comments and strings and returns
    /// the ones that qualify for inlining, in source order.
    static func inlineableImports(in content: String) -> [ImportStatement] {
        let bytes = Array(content.utf8)
        let count = bytes.count
        var statements: [ImportStatement] = []
        var index = 0

        func skipString(from start: Int) -> Int {
            let quote = bytes[start]
            var cursor = start + 1
            while cursor < count {
                if bytes[cursor] == UInt8(ascii: "\\") { cursor += 2; continue }
                if bytes[cursor] == quote { return cursor + 1 }
                cursor += 1
            }
            return count
        }

        func skipBlockComment(from start: Int) -> Int {
            var cursor = start + 2
            while cursor + 1 < count {
                if bytes[cursor] == UInt8(ascii: "*"), bytes[cursor + 1] == UInt8(ascii: "/") {
                    return cursor + 2
                }
                cursor += 1
            }
            return count
        }

        func skipLineComment(from start: Int) -> Int {
            var cursor = start + 2
            while cursor < count, bytes[cursor] != UInt8(ascii: "\n") { cursor += 1 }
            return cursor
        }

        func skipWhitespace(from start: Int) -> Int {
            var cursor = start
            while cursor < count {
                let byte = bytes[cursor]
                if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
                    || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") {
                    cursor += 1
                    continue
                }
                if byte == UInt8(ascii: "/"), cursor + 1 < count, bytes[cursor + 1] == UInt8(ascii: "*") {
                    cursor = skipBlockComment(from: cursor)
                    continue
                }
                if byte == UInt8(ascii: "/"), cursor + 1 < count, bytes[cursor + 1] == UInt8(ascii: "/") {
                    cursor = skipLineComment(from: cursor)
                    continue
                }
                break
            }
            return cursor
        }

        let keyword = Array("@import".utf8)

        while index < count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                index = skipString(from: index)
                continue
            }
            if byte == UInt8(ascii: "/"), index + 1 < count, bytes[index + 1] == UInt8(ascii: "*") {
                index = skipBlockComment(from: index)
                continue
            }
            if byte == UInt8(ascii: "/"), index + 1 < count, bytes[index + 1] == UInt8(ascii: "/") {
                index = skipLineComment(from: index)
                continue
            }
            guard byte == UInt8(ascii: "@"),
                  index + keyword.count <= count,
                  Array(bytes[index..<(index + keyword.count)]) == keyword
            else {
                index += 1
                continue
            }
            let statementStart = index
            var cursor = index + keyword.count
            // Require a separator so @importantthing does not match.
            guard cursor < count else { break }
            let separator = bytes[cursor]
            guard separator == UInt8(ascii: " ") || separator == UInt8(ascii: "\t")
                || separator == UInt8(ascii: "\n") || separator == UInt8(ascii: "\r")
                || separator == UInt8(ascii: "(")
            else {
                index = cursor
                continue
            }
            cursor = skipWhitespace(from: cursor)

            // Optional import options: (less), (once), ...
            var options: [String] = []
            if cursor < count, bytes[cursor] == UInt8(ascii: "(") {
                let optionsStart = cursor + 1
                var optionsEnd = optionsStart
                while optionsEnd < count, bytes[optionsEnd] != UInt8(ascii: ")") { optionsEnd += 1 }
                guard optionsEnd < count else { index = cursor; continue }
                options = String(decoding: bytes[optionsStart..<optionsEnd], as: UTF8.self)
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                cursor = skipWhitespace(from: optionsEnd + 1)
            }

            // Target: "url", 'url', or url(...).
            var target: String?
            if cursor < count, bytes[cursor] == UInt8(ascii: "\"") || bytes[cursor] == UInt8(ascii: "'") {
                let stringEnd = skipString(from: cursor)
                if stringEnd - cursor >= 2 {
                    target = String(decoding: bytes[(cursor + 1)..<(stringEnd - 1)], as: UTF8.self)
                }
                cursor = stringEnd
            } else if cursor + 4 <= count,
                      String(decoding: bytes[cursor..<min(cursor + 4, count)], as: UTF8.self).lowercased() == "url(" {
                var argumentEnd = cursor + 4
                while argumentEnd < count, bytes[argumentEnd] != UInt8(ascii: ")") {
                    if bytes[argumentEnd] == UInt8(ascii: "\"") || bytes[argumentEnd] == UInt8(ascii: "'") {
                        argumentEnd = skipString(from: argumentEnd)
                        continue
                    }
                    argumentEnd += 1
                }
                guard argumentEnd < count else { index = cursor; continue }
                var argument = String(decoding: bytes[(cursor + 4)..<argumentEnd], as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if argument.count >= 2, let first = argument.first,
                   first == "\"" || first == "'", argument.hasSuffix(String(first)) {
                    argument = String(argument.dropFirst().dropLast())
                }
                target = argument
                cursor = argumentEnd + 1
            }
            guard let url = target, !url.isEmpty else {
                index = statementStart + keyword.count
                continue
            }
            cursor = skipWhitespace(from: cursor)
            // Anything before the semicolon (a media query list) disqualifies inlining.
            guard cursor < count, bytes[cursor] == UInt8(ascii: ";") else {
                index = cursor
                continue
            }
            let statementEnd = cursor + 1
            index = statementEnd

            guard options.allSatisfy({ $0 == "less" || $0 == "once" }) else { continue }
            guard isInlineableRemoteURL(url, treatAsLess: options.contains("less")) else { continue }
            statements.append(ImportStatement(range: statementStart..<statementEnd, url: url))
        }
        return statements
    }

    private static func isInlineableRemoteURL(_ target: String, treatAsLess: Bool) -> Bool {
        guard let url = URL(string: target),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }
        if treatAsLess { return true }
        return url.path.lowercased().hasSuffix(".less")
    }
}
