import Foundation

/// An exclusive `flock` on a file, shared across the app and its extensions
/// through the app group. Each instance is one lock holder.
final class FileLock {
    private let fileDescriptor: Int32

    init?(filePath: String) {
        fileDescriptor = open(filePath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        if fileDescriptor == -1 { return nil }
    }

    deinit { close(fileDescriptor) }

    /// Waits for the lock until `limit`; false when it was not acquired.
    func lock(before limit: Date) -> Bool {
        while flock(fileDescriptor, LOCK_EX | LOCK_NB) == -1 {
            guard errno == EWOULDBLOCK || errno == EINTR, Date() < limit else { return false }
            usleep(10_000)
        }
        return true
    }

    @discardableResult
    func unlock() -> Bool {
        flock(fileDescriptor, LOCK_UN) == 0
    }
}
