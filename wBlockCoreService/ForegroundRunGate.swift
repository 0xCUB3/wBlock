/// Keeps the app's own update check or apply and an in-process auto-update run
/// apart. App work holds a count; a run starts only while the count is zero,
/// and new app work is refused until that run finishes.
public struct ForegroundRunGate: Sendable {
    public private(set) var foregroundWork = 0
    public private(set) var runActive = false

    public init() {}

    public mutating func beginForegroundWork() -> Bool {
        guard !runActive else { return false }
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

    public mutating func finishRun() {
        runActive = false
    }
}
