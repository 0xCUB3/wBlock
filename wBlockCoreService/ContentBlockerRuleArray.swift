import Foundation

/// Reads the top level of a content blocker rule array without building
/// Foundation objects for every rule. JSONSerialization needed about ten times
/// the file size in memory to answer how many rules there are.
enum ContentBlockerRuleArray {
    /// The number of rules, or nil unless the bytes are one array of objects
    /// with balanced brackets and terminated strings.
    static func count(_ json: Data) -> Int? {
        json.withUnsafeBytes { scan($0, keeping: nil)?.count }
    }

    /// The array cut to its first `maxRules` rules, or nil when it is not a rule array.
    static func truncated(_ json: Data, to maxRules: Int) -> (json: Data, ruleCount: Int)? {
        json.withUnsafeBytes { bytes in
            guard let scan = scan(bytes, keeping: max(maxRules, 0)) else { return nil }
            guard let end = scan.keptEnd, let base = bytes.baseAddress else { return (json, scan.count) }
            var cut = Data(bytes: base, count: end)
            cut.append(contentsOf: [0x5D])
            return (cut, scan.keptCount)
        }
    }

    /// `keptEnd` is the offset just past rule number `keeping`, when the array has more.
    private static func scan(
        _ raw: UnsafeRawBufferPointer, keeping: Int?
    ) -> (count: Int, keptCount: Int, keptEnd: Int?)? {
        guard let bytes = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let end = raw.count
        var count = 0
        var depth = 0
        var expectsElement = false
        var keptEnd: Int?
        var lastElementEnd: Int?
        var opened = false
        var closed = false
        var index = 0
        while index < end {
            let byte = bytes[index]
            index += 1
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D: continue
            case _ where closed: return nil
            case 0x5B where !opened:
                opened = true; depth = 1; expectsElement = true
                lastElementEnd = index
            case _ where !opened: return nil
            case 0x22:
                // Most of a rule array is string contents; jump to each closing quote.
                guard depth > 1, let close = closingQuote(bytes, from: index, end: end) else { return nil }
                index = close + 1
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
                    lastElementEnd = index
                }
            case 0x2C where depth == 1:
                guard !expectsElement else { return nil }
                expectsElement = true
            default:
                guard depth > 1 else { return nil }
            }
        }
        guard closed else { return nil }
        return (count, keeping.map { min($0, count) } ?? count, keptEnd)
    }

    /// The offset of the quote ending a string whose contents start at `start`:
    /// the first one not escaped by an odd run of backslashes.
    private static func closingQuote(_ bytes: UnsafePointer<UInt8>, from start: Int, end: Int) -> Int? {
        var from = start
        while from < end, let found = memchr(bytes + from, 0x22, end - from) {
            let quote = UnsafeRawPointer(found) - UnsafeRawPointer(bytes)
            var backslashes = 0
            while quote - backslashes > start, bytes[quote - backslashes - 1] == 0x5C { backslashes += 1 }
            if backslashes % 2 == 0 { return quote }
            from = quote + 1
        }
        return nil
    }
}
