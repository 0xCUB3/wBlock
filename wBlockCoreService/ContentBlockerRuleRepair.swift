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
        guard let ranges = topLevelObjectRanges(in: data), !ranges.isEmpty,
              await !compiles(data)
        else { return nil }
        let rejected = await rejectedIndices(data, ranges[...])
        guard !rejected.isEmpty else { return nil }
        let drop = Set(rejected)
        let kept = ranges.indices.filter { !drop.contains($0) }.map { ranges[$0] }
        let dropped = rejected.prefix(5).map { String(decoding: data[ranges[$0]], as: UTF8.self) }
        return (assemble(data, kept), dropped)
    }

    /// Byte ranges of each object in a top-level JSON array, or nil when the data
    /// is not one. Only brackets and string escapes are tracked, so no rule is
    /// built; WebKit judges each rule's contents when it compiles.
    static func topLevelObjectRanges(in data: Data) -> [Range<Int>]? {
        data.withUnsafeBytes { bytes -> [Range<Int>]? in
            let origin = data.startIndex
            var index = 0
            func skipWhitespace() {
                while index < bytes.count, ContentBlockerIncrementalCache.isJSONWhitespace(bytes[index]) { index += 1 }
            }
            /// The offset just past the `}` closing the object that starts at `start`.
            func objectEnd(from start: Int) -> Int? {
                var depth = 0
                var inString = false
                var escaped = false
                var cursor = start
                while cursor < bytes.count {
                    let byte = bytes[cursor]
                    cursor += 1
                    if inString {
                        if escaped {
                            escaped = false
                        } else if byte == 0x5C {
                            escaped = true
                        } else if byte == 0x22 {
                            inString = false
                        }
                    } else if byte == 0x22 {
                        inString = true
                    } else if byte == 0x7B || byte == 0x5B {
                        depth += 1
                    } else if byte == 0x7D || byte == 0x5D {
                        depth -= 1
                        if depth == 0 { return cursor }
                    }
                }
                return nil
            }

            var ranges: [Range<Int>] = []
            skipWhitespace()
            guard index < bytes.count, bytes[index] == 0x5B else { return nil }
            index += 1
            skipWhitespace()
            if index < bytes.count, bytes[index] == 0x5D {
                index += 1
            } else {
                while true {
                    skipWhitespace()
                    guard index < bytes.count, bytes[index] == 0x7B, let end = objectEnd(from: index) else { return nil }
                    ranges.append((origin + index)..<(origin + end))
                    index = end
                    skipWhitespace()
                    guard index < bytes.count else { return nil }
                    if bytes[index] == 0x2C {
                        index += 1
                        continue
                    }
                    guard bytes[index] == 0x5D else { return nil }
                    index += 1
                    break
                }
            }
            skipWhitespace()
            return index == bytes.count ? ranges : nil
        }
    }

    /// Indices of the rules WebKit rejects, found by compiling halves.
    private static func rejectedIndices(_ data: Data, _ ranges: ArraySlice<Range<Int>>) async -> [Int] {
        if ranges.count == 1 { return [ranges.startIndex] }
        let middle = ranges.startIndex + ranges.count / 2
        var rejected: [Int] = []
        for part in [ranges[..<middle], ranges[middle...]] where await !compiles(assemble(data, part)) {
            rejected += await rejectedIndices(data, part)
        }
        return rejected
    }

    /// The array of the rules at `ranges`, copied byte for byte from `data`.
    private static func assemble<Ranges: Sequence>(_ data: Data, _ ranges: Ranges) -> Data where Ranges.Element == Range<Int> {
        var json = Data([UInt8(ascii: "[")])
        for (index, range) in ranges.enumerated() {
            if index > 0 { json.append(UInt8(ascii: ",")) }
            json.append(data[range])
        }
        json.append(UInt8(ascii: "]"))
        return json
    }

    @MainActor
    private static func compiles(_ json: Data) async -> Bool {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-rule-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil,
              let store = WKContentRuleListStore(url: directory)
        else { return true }
        return await withCheckedContinuation { continuation in
            store.compileContentRuleList(
                forIdentifier: "check", encodedContentRuleList: String(decoding: json, as: UTF8.self)
            ) { list, error in
                continuation.resume(returning: list != nil && error == nil)
            }
        }
    }
}
