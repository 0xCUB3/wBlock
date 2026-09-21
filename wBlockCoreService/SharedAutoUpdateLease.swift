import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A kernel-backed, process-lifetime lease for shared auto-update work.
/// `flock` releases the lease automatically when the owning process exits.
public final class SharedAutoUpdateLease: @unchecked Sendable {
    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        #if canImport(Darwin)
        _ = flock(fileDescriptor, LOCK_UN)
        _ = close(fileDescriptor)
        #endif
    }

    /// Blocks the calling thread while polling. Use from actors that own their
    /// executor thread (the agent and extension), never from the main actor.
    public static func acquire(
        groupIdentifier: String,
        timeout: TimeInterval = 0.25
    ) -> SharedAutoUpdateLease? {
        #if canImport(Darwin)
        guard let descriptor = openLockFile(groupIdentifier: groupIdentifier) else { return nil }
        let deadline = Date().addingTimeInterval(max(0, timeout))
        repeat {
            if let lease = tryLock(descriptor) { return lease }
            if Date() >= deadline { break }
            usleep(pollIntervalMicroseconds)
        } while true
        closeLockFile(descriptor)
        #endif
        return nil
    }

    /// Suspends instead of blocking while polling, so the main actor stays
    /// responsive during a long wait on a running background update.
    public static func acquire(
        groupIdentifier: String,
        timeout: TimeInterval
    ) async -> SharedAutoUpdateLease? {
        #if canImport(Darwin)
        guard let descriptor = openLockFile(groupIdentifier: groupIdentifier) else { return nil }
        let deadline = Date().addingTimeInterval(max(0, timeout))
        repeat {
            if let lease = tryLock(descriptor) { return lease }
            if Date() >= deadline || Task.isCancelled { break }
            do {
                try await Task.sleep(nanoseconds: UInt64(pollIntervalMicroseconds) * 1_000)
            } catch {
                break
            }
        } while true
        closeLockFile(descriptor)
        #endif
        return nil
    }

    private static let pollIntervalMicroseconds: UInt32 = 10_000

    private static func openLockFile(groupIdentifier: String) -> Int32? {
        #if canImport(Darwin)
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else { return nil }

        do {
            try FileManager.default.createDirectory(
                at: containerURL,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }

        let lockURL = containerURL.appendingPathComponent("auto-update.run.lock")
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        return descriptor >= 0 ? descriptor : nil
        #else
        return nil
        #endif
    }

    private static func tryLock(_ descriptor: Int32) -> SharedAutoUpdateLease? {
        #if canImport(Darwin)
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return nil }
        return SharedAutoUpdateLease(fileDescriptor: descriptor)
        #else
        return nil
        #endif
    }

    private static func closeLockFile(_ descriptor: Int32) {
        #if canImport(Darwin)
        _ = close(descriptor)
        #endif
    }
}
