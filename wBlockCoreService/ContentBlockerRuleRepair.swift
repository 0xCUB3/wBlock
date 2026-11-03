import Foundation
import WebKit

/// Safari rejects a whole content blocker over a single rule its WebKit cannot
/// compile. When a reload fails, this compiles the output with the same WebKit,
/// finds the rejected rules by bisection, and drops them, so one bad rule costs
/// that rule instead of the blocker.
enum ContentBlockerRuleRepair {
    /// The output without the rules WebKit rejects, with how many were dropped,
    /// or nil when WebKit compiles it as is (the failure had another cause) or
    /// it is not a rule array.
    static func repaired(_ data: Data) async -> (data: Data, dropped: [String])? {
        guard let rules = try? JSONSerialization.jsonObject(with: data) as? [Any], !rules.isEmpty,
              await !compiles(rules)
        else { return nil }
        let rejected = await rejectedIndices(rules, offset: 0)
        guard !rejected.isEmpty else { return nil }
        let drop = Set(rejected)
        let kept = rules.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
        guard let repaired = try? JSONSerialization.data(withJSONObject: kept) else { return nil }
        let dropped = rejected.prefix(5).compactMap { index in
            (try? JSONSerialization.data(withJSONObject: rules[index])).map { String(decoding: $0, as: UTF8.self) }
        }
        return (repaired, dropped)
    }

    /// Indices of the rules WebKit rejects, found by compiling halves.
    private static func rejectedIndices(_ rules: [Any], offset: Int) async -> [Int] {
        if rules.count == 1 { return [offset] }
        let half = rules.count / 2
        var rejected: [Int] = []
        for (part, start) in [(Array(rules[..<half]), 0), (Array(rules[half...]), half)] where await !compiles(part) {
            rejected += await rejectedIndices(part, offset: offset + start)
        }
        return rejected
    }

    @MainActor
    private static func compiles(_ rules: [Any]) async -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: rules) else { return false }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-rule-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              let store = WKContentRuleListStore(url: directory)
        else { return true }
        return await withCheckedContinuation { continuation in
            store.compileContentRuleList(
                forIdentifier: "check", encodedContentRuleList: String(decoding: data, as: UTF8.self)
            ) { list, error in
                continuation.resume(returning: list != nil && error == nil)
            }
        }
    }
}
