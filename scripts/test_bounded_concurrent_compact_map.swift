import Foundation

@main
struct BoundedConcurrentCompactMapTests {
    static func main() async {
        let tracker = ConcurrencyTracker()

        let values = await boundedConcurrentCompactMap(
            Array(0..<8),
            maxConcurrent: 2
        ) { value in
            await tracker.begin()
            try? await Task.sleep(nanoseconds: 20_000_000)
            await tracker.end()
            return value.isMultiple(of: 2) ? value : nil
        }

        let maxConcurrency = await tracker.maxInFlight
        expectEqual(maxConcurrency, 2, "expected helper to respect the maxConcurrent limit")
        expectEqual(values.sorted(), [0, 2, 4, 6], "expected helper to keep non-nil results only")

        print("PASS")
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fputs("FAIL: \(message)\nactual: \(actual)\nexpected: \(expected)\n", stderr)
            exit(1)
        }
    }
}

private actor ConcurrencyTracker {
    private var inFlight = 0
    private(set) var maxInFlight = 0

    func begin() {
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
    }

    func end() {
        inFlight -= 1
    }
}
