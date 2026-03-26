import Foundation

/// Runs an async transform with bounded concurrency and keeps only non-nil outputs.
/// Results are returned in completion order.
public func boundedConcurrentCompactMap<Item: Sendable, Output: Sendable>(
    _ items: [Item],
    maxConcurrent: Int? = nil,
    transform: @Sendable @escaping (Item) async -> Output?
) async -> [Output] {
    guard !items.isEmpty else { return [] }

    let limit: Int
    if let maxConcurrent {
        limit = maxConcurrent
    } else {
        #if os(macOS)
        limit = 3
        #else
        limit = 2
        #endif
    }

    var iterator = items.makeIterator()
    var outputs: [Output] = []

    await withTaskGroup(of: Output?.self) { group in
        func enqueueNext() {
            guard let item = iterator.next() else { return }
            group.addTask { await transform(item) }
        }

        for _ in 0..<min(limit, items.count) {
            enqueueNext()
        }

        while let output = await group.next() {
            if let output {
                outputs.append(output)
            }
            enqueueNext()
        }
    }

    return outputs
}
