import Foundation

// App group locks and suspension (0xDEAD10CC in 3.2.3 on iOS and macOS):
// a held lock keeps the process from suspending, imminent suspension refuses
// new locks, and the process suspends as soon as held ones are released.

/// Stands in for performExpiringActivity: runs each activity on its own
/// thread and lets the test expire it, as the system does before suspending.
final class FakeSystem: @unchecked Sendable {
    let condition = NSCondition()
    var bodies: [@Sendable (Bool) -> Void] = []
    var openActivities = 0
    var noBackgroundTime = false

    func begin(_ body: @escaping @Sendable (Bool) -> Void) {
        condition.lock()
        let expiredAtOnce = noBackgroundTime
        bodies.append(body)
        openActivities += 1
        condition.unlock()
        Thread.detachNewThread { [self] in
            body(expiredAtOnce)
            condition.lock(); openActivities -= 1; condition.broadcast(); condition.unlock()
        }
    }

    /// Calls the latest activity's expiration handler alongside its body.
    func expire() {
        condition.lock()
        let body = bodies.last!
        openActivities += 1
        condition.unlock()
        Thread.detachNewThread { [self] in
            body(true)
            condition.lock(); openActivities -= 1; condition.broadcast(); condition.unlock()
        }
    }

    func waitForActivities(_ count: Int, timeout: TimeInterval = 2) -> Bool {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while openActivities != count { if !condition.wait(until: deadline) { return false } }
        return true
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() { lock.lock(); count += 1; lock.unlock() }

    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

func expect(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: \(message)"); exit(1) }
}

@main
struct FileLockSuspensionTest {
    static func main() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("file-lock-\(UUID())")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("a.lock").path
        let otherPath = directory.appendingPathComponent("b.lock").path

        // A held lock keeps the activity open until it is released.
        let system = FakeSystem()
        let guardian = SuspensionGuard(beginActivity: system.begin)
        let lock = FileLock(filePath: path, suspension: guardian)!
        expect(lock.tryLock(), "takes a free lock")
        expect(system.waitForActivities(1), "holding a lock opens one activity")
        lock.unlock()
        expect(system.waitForActivities(0), "releasing the last lock ends the activity")

        // Imminent suspension refuses new locks and lets go once held ones are released.
        expect(lock.tryLock(), "locks again after the activity ended")
        system.expire()
        Thread.sleep(forTimeInterval: 0.1)
        let other = FileLock(filePath: otherPath, suspension: guardian)!
        expect(!other.tryLock(), "refuses a new lock once suspension is imminent")
        expect(!other.lock(before: Date().addingTimeInterval(5)), "a waiting lock gives up instead of polling on")
        let start = Date()
        lock.unlock()
        expect(system.waitForActivities(0), "releasing the held lock ends the expired activity")
        expect(Date().timeIntervalSince(start) < 1, "suspends as soon as the lock is released, not after the unwind timeout")

        // Without background time a lock is never taken.
        system.noBackgroundTime = true
        expect(!other.tryLock(), "no lock without background time")
        expect(system.waitForActivities(0), "the refused attempt leaves no activity open")

        // After resuming, locks work again.
        system.noBackgroundTime = false
        expect(other.tryLock(), "locks again after resuming")
        other.unlock()
        expect(system.waitForActivities(0), "and lets go again")

        // The kernel lock itself still excludes another holder.
        let first = FileLock(filePath: path, suspension: guardian)!
        let second = FileLock(filePath: path, suspension: guardian)!
        expect(first.tryLock(), "first holder")
        expect(!second.tryLock(), "second holder waits")
        first.unlock()
        expect(second.tryLock(), "second holder gets it after release")
        second.unlock()
        expect(system.waitForActivities(0), "every attempt was balanced")

        // A contended wait holds one activity for the whole wait, not one per poll.
        // The holder has no suspension guard, so only the contender opens activities.
        let holder = FileLock(filePath: path, suspension: nil)!
        expect(holder.tryLock(), "holder takes the kernel lock")
        let contender = FileLock(filePath: path, suspension: guardian)!
        let opened = system.bodies.count
        expect(!contender.lock(before: Date().addingTimeInterval(0.3)), "contended lock times out")
        expect(system.bodies.count - opened == 1, "a contended wait opens one activity, not one per poll")
        expect(system.waitForActivities(0), "the timed-out wait leaves no activity open")
        holder.unlock()

        // An activity that never starts must not let a lock through without its assertion.
        let stalledBegins = Counter()
        let stalled = SuspensionGuard { _ in stalledBegins.increment() }
        let stalledLock = FileLock(filePath: otherPath, suspension: stalled)!
        expect(!stalledLock.tryLock(), "no lock when the activity never starts")
        let bare = FileLock(filePath: otherPath, suspension: nil)!
        expect(bare.tryLock(), "the kernel lock was not taken by the refused attempt")
        bare.unlock()
        expect(!stalledLock.tryLock(), "a second attempt is refused the same way")
        expect(stalledBegins.value == 2, "an abandoned activity is reopened on the next attempt")

        print("file lock suspension: ok")
    }
}
