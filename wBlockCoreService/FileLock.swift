import Foundation

/// An exclusive `flock` on a file, shared across the app and its extensions
/// through the app group. Each instance is one lock holder, and every app
/// group lock goes through this type.
///
/// iOS kills a process that suspends while holding one (0xDEAD10CC). So on
/// iOS, while any lock is held, `SuspensionGuard.shared` keeps the process
/// from suspending. Once suspension is imminent it refuses new locks, and the
/// process suspends as soon as the held ones are released. macOS has no API
/// for this, so there the guard is nil.
final class FileLock {
    private let fileDescriptor: Int32
    private let suspension: SuspensionGuard?
    private var isLocked = false

    init?(filePath: String, suspension: SuspensionGuard? = SuspensionGuard.shared) {
        fileDescriptor = open(filePath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        if fileDescriptor == -1 { return nil }
        self.suspension = suspension
    }

    deinit {
        unlock()
        close(fileDescriptor)
    }

    /// One attempt; false when another holder has it or suspension is imminent.
    func tryLock() -> Bool {
        if isLocked { return true }
        guard suspension?.enter() ?? true else { return false }
        var result: Int32
        repeat { result = flock(fileDescriptor, LOCK_EX | LOCK_NB) } while result == -1 && errno == EINTR
        guard result == 0 else {
            suspension?.leave()
            return false
        }
        isLocked = true
        return true
    }

    /// Waits for the lock until `limit`; false when it was not acquired.
    func lock(before limit: Date) -> Bool {
        while !tryLock() {
            guard Date() < limit, suspension?.isRefusing != true else { return false }
            usleep(10_000)
        }
        return true
    }

    func unlock() {
        guard isLocked else { return }
        isLocked = false
        _ = flock(fileDescriptor, LOCK_UN)
        suspension?.leave()
    }

    /// Runs `body` holding the lock at `url`, creating its directory if needed.
    static func withLock<T>(at url: URL, timeout: TimeInterval, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let lock = FileLock(filePath: url.path) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let limit = timeout.isFinite ? Date().addingTimeInterval(timeout) : .distantFuture
        guard lock.lock(before: limit) else { throw POSIXError(.ETIMEDOUT) }
        defer { lock.unlock() }
        return try body()
    }
}

/// Counts the app group locks this process holds and keeps a
/// suspension-deferring activity open while the count is above zero.
final class SuspensionGuard: @unchecked Sendable {
    /// Starts an expiring activity and calls `body(false)` on another thread,
    /// holding its assertion until that call returns. `body(true)` comes
    /// instead, or concurrently, when suspension is imminent.
    typealias BeginActivity = (_ body: @escaping @Sendable (_ expired: Bool) -> Void) -> Void

    #if os(iOS)
    static let shared: SuspensionGuard? = SuspensionGuard { body in
        ProcessInfo.processInfo.performExpiringActivity(withReason: "wBlock app group lock", using: body)
    }
    #else
    static let shared: SuspensionGuard? = nil
    #endif

    private static let startTimeout: TimeInterval = 1
    /// How long an expired activity waits for held locks before letting go.
    private static let unwindTimeout: TimeInterval = 3

    private let beginActivity: BeginActivity
    private let condition = NSCondition()
    private var held = 0
    private var activityOpen = false
    private var activityStarted = false
    private var expired = false

    init(beginActivity: @escaping BeginActivity) {
        self.beginActivity = beginActivity
    }

    /// Whether new locks are refused because suspension is imminent.
    var isRefusing: Bool {
        condition.lock()
        defer { condition.unlock() }
        return activityOpen && expired
    }

    /// Counts a lock about to be taken; false when suspension is imminent.
    func enter() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        // Counted first, so a newly started activity sees the lock it covers.
        held += 1
        if !activityOpen {
            activityOpen = true
            activityStarted = false
            expired = false
            condition.unlock()
            beginActivity { [self] isExpired in activity(expired: isExpired) }
            condition.lock()
            let deadline = Date().addingTimeInterval(Self.startTimeout)
            while !activityStarted && condition.wait(until: deadline) {}
        }
        guard !expired else {
            held -= 1
            condition.broadcast()
            return false
        }
        return true
    }

    func leave() {
        condition.lock()
        held -= 1
        condition.broadcast()
        condition.unlock()
    }

    private func activity(expired isExpired: Bool) {
        condition.lock()
        defer { condition.unlock() }
        activityStarted = true
        if isExpired { expired = true }
        condition.broadcast()
        // The assertion lasts as long as this call. Before expiry it waits for
        // the last lock; after it, it gives held locks a moment to finish.
        let deadline = isExpired ? Date().addingTimeInterval(Self.unwindTimeout) : .distantFuture
        while held > 0 && (isExpired || !expired) && condition.wait(until: deadline) {}
        if held == 0 || isExpired { activityOpen = false }
    }
}
