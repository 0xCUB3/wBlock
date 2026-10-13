//
//  CrossTargetExceptionReplicator.swift
//  wBlockCoreService
//
//  Safari evaluates each content blocker extension on its own, so an `@@`
//  exception only cancels block rules compiled into the same extension.
//  Selected lists are spread across the extensions by size, which separates an
//  exception from the block it was written for whenever the two come from
//  different lists. EasyPrivacy blocks `bing.com/fd/ls/GLinkPing.aspx?` and
//  AdGuard Tracking Protection excepts it; with the lists in different slots
//  every Bing result tap failed as blocked by a content blocker (issue #836).
//
//  Network exceptions from every other selected list are copied into a target
//  when that target compiles a block rule the exception can plausibly cancel.
//  Copying an exception that cancels nothing is harmless, so matching errs on
//  the side of inclusion while staying cheap enough for 100k-line lists.
//

import CryptoKit
import Foundation

public enum CrossTargetExceptionReplicator {
    struct NetworkRule {
        let isException: Bool
        /// Pattern portion in rule-identity form (lowercased unless regex).
        let pattern: String
        /// `host` for `||host`-anchored patterns without wildcards.
        let anchoredHost: String?

        init?(line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard FilterRuleAnalysis.isRuleLine(trimmed), !trimmed.hasPrefix("!#") else { return nil }
            if trimmed.contains("##") || trimmed.contains("#@") || trimmed.contains("#?#")
                || trimmed.contains("#$#") || trimmed.contains("#%#") {
                return nil
            }
            let identity = FilterRuleAnalysis.ruleIdentity(trimmed)
            isException = identity.hasPrefix("@@")
            let body = isException ? String(identity.dropFirst(2)) : identity
            guard !body.isEmpty else { return nil }

            var pattern = body
            var options = ""
            if body.hasPrefix("/") {
                var escaped = false
                var close: String.Index?
                for index in body.indices.dropFirst() {
                    if escaped { escaped = false; continue }
                    if body[index] == "\\" { escaped = true; continue }
                    if body[index] == "/" { close = index; break }
                }
                if let close {
                    let end = body.index(after: close)
                    pattern = String(body[..<end])
                    if end < body.endIndex, body[end] == "$" {
                        options = String(body[body.index(after: end)...])
                    }
                }
            } else if let dollar = body.firstIndex(of: "$") {
                pattern = String(body[..<dollar])
                options = String(body[body.index(after: dollar)...])
            }
            guard !pattern.isEmpty else { return nil }
            // Only the DNR generator understands these; the converter drops them.
            if options.contains("removeparam") || options.contains("urltransform") { return nil }
            self.pattern = pattern

            guard pattern.hasPrefix("||"), !pattern.contains("*") else {
                anchoredHost = nil
                return
            }
            let rest = pattern.dropFirst(2)
            let hostEnd = rest.firstIndex { "^/$|?".contains($0) } ?? rest.endIndex
            let host = String(rest[..<hostEnd])
            anchoredHost = host.contains(".") ? host : nil
        }

        /// True when the rule matches a whole host: `||host^`, `||host`, `||host/`.
        var isBareHost: Bool {
            guard let anchoredHost else { return false }
            let rest = pattern.dropFirst(2 + anchoredHost.count)
            return rest.isEmpty || rest == "^" || rest == "^|" || rest == "/"
        }

        /// Pattern with trailing anchors removed, for prefix comparison.
        var prefixKey: Substring {
            var key = Substring(pattern)
            while let last = key.last, last == "^" || last == "|" { key = key.dropLast() }
            return key
        }
    }

    /// Exceptions from other blockers' lists that a target needs. Feed it
    /// each list as it is written so no list text has to stay around.
    struct Replication {
        private var patterns = Set<String>()
        private var bareHosts = Set<String>()
        private var candidates: [[(line: String, rule: NetworkRule)]] = []

        /// A list compiled into this target.
        mutating func addTarget(_ source: String, isCancelled: () -> Bool) throws {
            for raw in source.split(whereSeparator: \.isNewline) {
                if isCancelled() { throw CancellationError() }
                guard let rule = NetworkRule(line: String(raw)), !rule.isException else { continue }
                patterns.insert(rule.pattern)
                if rule.isBareHost, let host = rule.anchoredHost { bareHosts.insert(host) }
            }
        }

        /// A list compiled into another target.
        mutating func addCandidate(_ source: String, isCancelled: () -> Bool) throws {
            candidates.append(try CrossTargetExceptionReplicator.exceptions(of: source, isCancelled: isCancelled))
        }

        /// Exception lines this target should also receive, in order of first
        /// appearance and without duplicates.
        func exceptions(isCancelled: () -> Bool) throws -> [String] {
            guard !patterns.isEmpty else { return [] }
            let sortedPatterns = patterns.sorted()
            var seen = Set<String>()
            var output: [String] = []
            for (line, rule) in candidates.joined() {
                if isCancelled() { throw CancellationError() }
                guard canBeCancelled(by: rule, sortedPatterns: sortedPatterns),
                      seen.insert(FilterRuleAnalysis.ruleIdentity(line)).inserted
                else { continue }
                output.append(line)
            }
            return output
        }

        private func canBeCancelled(by exception: NetworkRule, sortedPatterns: [String]) -> Bool {
            if patterns.contains(exception.pattern) { return true }
            guard let host = exception.anchoredHost else { return false }

            // A whole-host block on this host or a parent domain covers the URL.
            var labels = host.split(separator: ".")
            while labels.count >= 2 {
                if bareHosts.contains(labels.joined(separator: ".")) { return true }
                labels.removeFirst()
            }

            let key = exception.prefixKey
            guard key.count >= 4 else { return false }
            // A block whose pattern is a prefix of the exception matches the same URLs.
            var end = key.index(key.startIndex, offsetBy: 3)
            while end < key.endIndex {
                end = key.index(after: end)
                if patterns.contains(String(key[..<end])) { return true }
            }
            // An exception whose pattern is a prefix of a block is broader than it.
            var low = 0
            var high = sortedPatterns.count
            while low < high {
                let mid = (low + high) / 2
                if sortedPatterns[mid] < key { low = mid + 1 } else { high = mid }
            }
            return low < sortedPatterns.count && sortedPatterns[low].hasPrefix(key)
        }
    }

    private struct ExceptionsKey: Hashable { let digest: String }

    /// Network exceptions of one list text. Every other blocker of an Apply
    /// asks for them, so an Apply parses each text once and keeps only these.
    private static func exceptions(of source: String, isCancelled: () -> Bool) throws -> [(line: String, rule: NetworkRule)] {
        func parse() throws -> [(line: String, rule: NetworkRule)] {
            var exceptions: [(line: String, rule: NetworkRule)] = []
            for raw in source.split(whereSeparator: \.isNewline) {
                if isCancelled() { throw CancellationError() }
                let line = String(raw).trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("@@"), let rule = NetworkRule(line: line) else { continue }
                exceptions.append((line, rule))
            }
            return exceptions
        }
        guard let scope = CompilationScope.current else { return try parse() }
        return try scope.memoized(ExceptionsKey(digest: SHA256.hash(data: Data(source.utf8)).description), parse)
    }
}
