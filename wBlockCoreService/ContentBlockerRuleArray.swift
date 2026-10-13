import Foundation

/// Reads the top level of a content blocker rule array without building
/// Foundation objects for every rule. JSONSerialization needed about ten times
/// the file size in memory to answer how many rules there are.
enum ContentBlockerRuleArray {
    /// The number of rules, or nil unless the bytes are one array of objects
    /// with balanced brackets and terminated strings.
    static func count<Bytes: Collection<UInt8>>(_ bytes: Bytes) -> Int? {
        scan(bytes, keeping: nil)?.count
    }

    static func count(_ json: String) -> Int? {
        var json = json
        return json.withUTF8 { count($0) }
    }

    /// The array cut to its first `maxRules` rules, or nil when it is not a rule array.
    static func truncated(_ json: String, to maxRules: Int) -> (json: String, ruleCount: Int)? {
        var json = json
        return json.withUTF8 { bytes in
            guard let scan = scan(bytes, keeping: max(maxRules, 0)) else { return nil }
            guard let end = scan.keptEnd else { return (String(decoding: bytes, as: UTF8.self), scan.count) }
            return (String(decoding: bytes[..<end], as: UTF8.self) + "]", scan.keptCount)
        }
    }

    /// `keptEnd` is the offset just past rule number `keeping`, when the array has more.
    private static func scan<Bytes: Collection<UInt8>>(
        _ bytes: Bytes, keeping: Int?
    ) -> (count: Int, keptCount: Int, keptEnd: Bytes.Index?)? {
        var count = 0
        var depth = 0
        var inString = false
        var escaped = false
        var expectsElement = false
        var keptEnd: Bytes.Index?
        var lastElementEnd: Bytes.Index?
        var opened = false
        var closed = false
        var index = bytes.startIndex
        while index != bytes.endIndex {
            let byte = bytes[index]
            defer { index = bytes.index(after: index) }
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
                continue
            }
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D: continue
            case _ where closed: return nil
            case 0x5B where !opened:
                opened = true; depth = 1; expectsElement = true
                lastElementEnd = bytes.index(after: index)
            case _ where !opened: return nil
            case 0x22: guard depth > 1 else { return nil }; inString = true
            case 0x7B, 0x5B:
                if depth == 1 {
                    guard byte == 0x7B, expectsElement else { return nil }
                    expectsElement = false
                    if count == keeping { keptEnd = keptEnd ?? lastElementEnd }
                    count += 1
                }
                depth += 1
            case 0x7D, 0x5D:
                depth -= 1
                if depth == 0 {
                    guard byte == 0x5D, !expectsElement || count == 0 else { return nil }
                    closed = true
                } else if depth == 1 {
                    lastElementEnd = bytes.index(after: index)
                }
            case 0x2C where depth == 1:
                guard !expectsElement else { return nil }
                expectsElement = true
            default:
                guard depth > 1 else { return nil }
            }
        }
        guard closed, !inString else { return nil }
        return (count, keeping.map { min($0, count) } ?? count, keptEnd)
    }
}
