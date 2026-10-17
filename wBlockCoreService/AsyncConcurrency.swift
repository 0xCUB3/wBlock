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
public func boundedConcurrentForEach<Item: Sendable, Result: Sendable>(
    _ items: [Item],
    maxConcurrent: Int? = nil,
    operation: @Sendable @escaping (Item) async -> Result,
    onResult: (Result) async -> Void
) async {
    guard !items.isEmpty else { return }

    let limit: Int
    if let maxConcurrent {
        limit = max(1, maxConcurrent)
    } else {
        #if os(macOS)
        limit = 3
        #else
        limit = 2
        #endif
    }

    var iterator = items.makeIterator()

    await withTaskGroup(of: Result.self) { group in
        func enqueueNext() {
            guard let item = iterator.next() else { return }
            group.addTask { await operation(item) }
        }

        for _ in 0..<min(limit, items.count) {
            enqueueNext()
        }

        while let result = await group.next() {
            guard !Task.isCancelled else {
                group.cancelAll()
                break
            }
            await onResult(result)
            guard !Task.isCancelled else {
                group.cancelAll()
                break
            }
            enqueueNext()
        }
    }
}
