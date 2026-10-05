import Foundation

/// Work shared by the blockers of one Apply. It lives only as long as the
/// Apply, so idle processes keep nothing, and direct callers outside an Apply
/// compute everything themselves.
final class CompilationScope: @unchecked Sendable {
    @TaskLocal static var current: CompilationScope?

    private final class Entry {
        let lock = NSLock()
        var value: Any?
    }

    private let lock = NSLock()
    private var entries: [AnyHashable: Entry] = [:]

    /// Blockers that ask for the same key wait for the first one to finish
    /// instead of repeating its work; different keys run in parallel. Errors,
    /// including cancellation, are not cached.
    func memoized<Key: Hashable, Value>(_ key: Key, _ compute: () throws -> Value) rethrows -> Value {
        lock.lock()
        let entry = entries[key] ?? Entry()
        entries[key] = entry
        lock.unlock()

        entry.lock.lock()
        defer { entry.lock.unlock() }
        if let value = entry.value as? Value { return value }
        let value = try compute()
        entry.value = value
        return value
    }
}
