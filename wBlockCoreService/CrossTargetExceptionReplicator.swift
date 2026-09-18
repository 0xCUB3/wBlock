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

    /// Block-rule index for one target's input.
    struct BlockIndex {
        private(set) var patterns = Set<String>()
        private(set) var bareHosts = Set<String>()
        private var sortedPatterns: [String] = []

        init(sources: [String], isCancelled: () -> Bool) throws {
            for source in sources {
                for line in source.split(whereSeparator: \.isNewline) {
                    if isCancelled() { throw CancellationError() }
                    guard let rule = NetworkRule(line: String(line)), !rule.isException else { continue }
                    patterns.insert(rule.pattern)
                    if rule.isBareHost, let host = rule.anchoredHost { bareHosts.insert(host) }
                }
            }
            sortedPatterns = patterns.sorted()
        }

        var isEmpty: Bool { patterns.isEmpty }

        func canBeCancelled(by exception: NetworkRule) -> Bool {
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

    /// Exception lines from `candidateSources` that a target compiling
    /// `targetSources` should also receive, in rule-identity order of first
    /// appearance and without duplicates.
    public static func replicatedExceptions(
        targetSources: [String],
        candidateSources: [String],
        isCancelled: () -> Bool = { false }
    ) throws -> [String] {
        let index = try BlockIndex(sources: targetSources, isCancelled: isCancelled)
        guard !index.isEmpty else { return [] }

        var seen = Set<String>()
        var output: [String] = []
        for source in candidateSources {
            for raw in source.split(whereSeparator: \.isNewline) {
                if isCancelled() { throw CancellationError() }
                let line = String(raw).trimmingCharacters(in: .whitespaces)
                guard let rule = NetworkRule(line: line), rule.isException,
                      index.canBeCancelled(by: rule),
                      seen.insert(FilterRuleAnalysis.ruleIdentity(line)).inserted
                else { continue }
                output.append(line)
            }
        }
        return output
    }
}
