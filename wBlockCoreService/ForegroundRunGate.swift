/// Keeps the app's own update check or apply and an in-process auto-update run
/// apart. App work holds a count; a run starts only while the count is zero.
/// App work asked for during a run waits for it to finish: refused outright,
/// an apply asked for as the foreground catch-up started never ran.
public struct ForegroundRunGate: Sendable {
    public private(set) var foregroundWork = 0
    public private(set) var runActive = false
    private var waiters: [@Sendable () -> Void] = []

    public init() {}

    /// Claims app work, or during a run queues `resume` for when the run
    /// finishes and returns false; the caller claims again then.
    public mutating func beginForegroundWork(orWait resume: @escaping @Sendable () -> Void) -> Bool {
        guard !runActive else {
            waiters.append(resume)
            return false
        }
        foregroundWork += 1
        return true
    }

    public mutating func endForegroundWork() {
        foregroundWork = max(0, foregroundWork - 1)
    }

    public mutating func startRun() -> Bool {
        guard foregroundWork == 0 else { return false }
        runActive = true
        return true
    }

    /// Ends the run and hands back the waiting app work to resume.
    public mutating func finishRun() -> [@Sendable () -> Void] {
        runActive = false
        defer { waiters = [] }
        return waiters
    }
}
