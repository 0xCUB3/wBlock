import Foundation
internal import WBEngine

/// Work shared by the blockers of one Apply. It lives only as long as the
/// Apply, so idle processes keep nothing, and direct callers outside an Apply
/// compute everything themselves.
final class CompilationScope: @unchecked Sendable {
    @TaskLocal static var current: CompilationScope?

    /// Blockers compiled at once. Past freezes, watchdog kills, and Safari
    /// compiler crashes came from memory and time pressure on phones,
    /// background refreshes, and smaller Macs, so only a foreground Apply on a
    /// Mac with at least 16 GB, 8 cores, normal thermal state, and Low Power
    /// Mode off gets more. Phones with 4 GB or less compile one at a time: each
    /// compile holds the plan's parsed lists plus its own output.
    static func targetCapacity(interactive: Bool) -> Int {
        let info = ProcessInfo.processInfo
        #if os(macOS)
        let roomy = interactive
            && info.physicalMemory >= 16 << 30
            && info.activeProcessorCount >= 8
            && info.thermalState.rawValue <= ProcessInfo.ThermalState.fair.rawValue
            && !info.isLowPowerModeEnabled
        return roomy ? 5 : 3
        #else
        return info.physicalMemory <= 4 << 30 ? 1 : 2
        #endif
    }

    /// Whether the engine keeps each list's parse between applies, so a plan
    /// after an edit parses only the changed list. Phones and Macs with 4 GB or
    /// less drop it when their apply ends, as they drop the rest of the plan.
    static let keepsParsedLists: Bool = {
        #if os(macOS)
        return ProcessInfo.processInfo.physicalMemory > 4 << 30
        #else
        return false
        #endif
    }()

    deinit {
        if !Self.keepsParsedLists { WBEngine.clearParseCache() }
    }

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
