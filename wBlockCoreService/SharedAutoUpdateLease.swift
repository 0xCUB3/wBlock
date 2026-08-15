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

    public static func acquire(
        groupIdentifier: String,
        timeout: TimeInterval = 0.25
    ) -> SharedAutoUpdateLease? {
        #if canImport(Darwin)
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else { return nil }

        let lockURL = containerURL.appendingPathComponent("auto-update.run.lock")
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        let deadline = Date().addingTimeInterval(max(0, timeout))
        repeat {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                return SharedAutoUpdateLease(fileDescriptor: descriptor)
            }
            if Date() >= deadline { break }
            usleep(10_000)
        } while true
        _ = close(descriptor)
        return nil
        #else
        return nil
        #endif
    }
}
