import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A kernel-backed, process-lifetime lease for shared auto-update work.
/// `flock` releases the lease automatically when the owning process exits.
public final class SharedAutoUpdateLease: @unchecked Sendable {
    private let lock: FileLock

    private init(lock: FileLock) {
        self.lock = lock
    }

    /// Blocks the calling thread while polling. Use from actors that own their
    /// executor thread (the agent and extension), never from the main actor.
    public static func acquire(
        groupIdentifier: String,
        timeout: TimeInterval = 0.25
    ) -> SharedAutoUpdateLease? {
        guard let lock = openLock(groupIdentifier: groupIdentifier),
              lock.lock(before: Date().addingTimeInterval(max(0, timeout)))
        else { return nil }
        return SharedAutoUpdateLease(lock: lock)
    }

    /// Suspends instead of blocking while polling, so the main actor stays
    /// responsive during a long wait on a running background update.
    public static func acquire(
        groupIdentifier: String,
        timeout: TimeInterval
    ) async -> SharedAutoUpdateLease? {
        guard let lock = openLock(groupIdentifier: groupIdentifier) else { return nil }
        let deadline = Date().addingTimeInterval(max(0, timeout))
        repeat {
            if lock.tryLock() { return SharedAutoUpdateLease(lock: lock) }
            if Date() >= deadline || Task.isCancelled { break }
            do {
                try await Task.sleep(nanoseconds: 10_000_000)
            } catch {
                break
            }
        } while true
        return nil
    }

    private static func openLock(groupIdentifier: String) -> FileLock? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else { return nil }
        try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        return FileLock(filePath: containerURL.appendingPathComponent("auto-update.run.lock").path)
    }
}
