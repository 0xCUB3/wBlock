import Foundation

public enum CloudSyncUploadAction: Equatable {
    case startNow(String)
    case deferUntilIdle
}

public struct CloudSyncUploadCoordinator {
    private var deferredTrigger: String?

    public init() {}

    public mutating func actionForUploadRequest(
        trigger: String,
        isSyncing: Bool
    ) -> CloudSyncUploadAction {
        guard isSyncing else {
            return .startNow(trigger)
        }

        deferredTrigger = trigger
        return .deferUntilIdle
    }

    public mutating func takeDeferredTrigger() -> String? {
        defer { deferredTrigger = nil }
        return deferredTrigger
    }
}

/// Runs an async operation on each item with bounded concurrency, calling `onResult`
/// for each completed result in completion order. Platform-aware default concurrency.
/// 
/// Concurrency: macOS (8), iOS/iPadOS (4) - higher than before for faster filter processing
public func boundedConcurrentForEach<Item: Sendable, Result: Sendable>(
    _ items: [Item],
    maxConcurrent: Int? = nil,
    operation: @Sendable @escaping (Item) async -> Result,
    onResult: (Result) async -> Void
) async {
    guard !items.isEmpty else { return }

    let limit: Int = maxConcurrent ?? (
        #if os(macOS)
        8
        #else
        4
        #endif
    )

    await withTaskGroup(of: (Int, Result).self) { group in
        var pendingItems = items
        while !pendingItems.isEmpty {
            for item in Array(pendingItems.prefix(limit)) {
                pendingItems.removeFirst()
                group.addTask(priority: .utility) {
                    let result = await operation(item)
                    return (item, result)
                }
            }
            if let (_, result) = await group.next() {
                await onResult(result)
            }
        }
        await group.waitForAll()
    }
}

/// Runs an async transform with bounded concurrency and keeps only non-nil outputs.
/// Results are returned in completion order.
@available(*, deprecated, message: "Use boundedConcurrentCompactMap instead")
public func boundedConcurrentCompactMap<Item: Sendable, Output: Sendable>(
    _ items: [Item],
    maxConcurrent: Int? = nil,
    transform: @Sendable @escaping (Item) async -> Output?
) async -> [Output] {
    var outputs: [Output] = []
    await boundedConcurrentForEach(
        items,
        maxConcurrent: maxConcurrent,
        operation: transform
    ) { output in
        if let output { outputs.append(output) }
    }
    return outputs
}
