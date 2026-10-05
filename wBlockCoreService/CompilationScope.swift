import Foundation

/// Work shared by the blockers of one Apply. It lives only as long as the
/// Apply, so idle processes keep nothing, and direct callers outside an Apply
/// compute everything themselves.
final class CompilationScope: @unchecked Sendable {
    @TaskLocal static var current: CompilationScope?

    /// Workers one large list may be parsed with. Above one only for an
    /// interactive Apply on a Mac with room to spare.
    let parseWorkers: Int

    init(parseWorkers: Int = 1) {
        self.parseWorkers = max(1, parseWorkers)
    }

    /// Blockers compiled at once and parse workers per list. Past freezes,
    /// watchdog kills, and Safari compiler crashes came from memory and time
    /// pressure on phones, background refreshes, and smaller Macs, so only a
    /// foreground Apply on a Mac with at least 16 GB, 8 cores, normal thermal
    /// state, and Low Power Mode off gets more. Everything else keeps the
    /// limits that shipped before.
    static func capacity(interactive: Bool) -> (targets: Int, parseWorkers: Int) {
        #if os(macOS)
        let info = ProcessInfo.processInfo
        let roomy = interactive
            && info.physicalMemory >= 16 << 30
            && info.activeProcessorCount >= 8
            && info.thermalState.rawValue <= ProcessInfo.ThermalState.fair.rawValue
            && !info.isLowPowerModeEnabled
        return roomy ? (5, 2) : (3, 1)
        #else
        return (2, 1)
        #endif
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
