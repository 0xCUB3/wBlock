import Foundation

/// App-group backed lifecycle state for the Safari popup's headless filter update.
/// The updater remains owned by SharedAutoUpdateManager; this store only exposes a
/// small, restart-safe status contract to the extension UI.
public enum FilterUpdatePopupStatus {
    public enum State: String, Sendable {
        case idle
        case running
        case succeeded
        case noChange = "no_change"
        case failed
    }

    public struct Snapshot: Sendable {
        public let state: State
        public let startedAt: TimeInterval?
        public let finishedAt: TimeInterval?
        public let checkedFilters: Int
        public let updatedFilters: Int
        public let error: String?

        public init(
            state: State,
            startedAt: TimeInterval?,
            finishedAt: TimeInterval?,
            checkedFilters: Int,
            updatedFilters: Int,
            error: String?
        ) {
            self.state = state
            self.startedAt = startedAt
            self.finishedAt = finishedAt
            self.checkedFilters = checkedFilters
            self.updatedFilters = updatedFilters
            self.error = error
        }
    }

    private static let stateKey = "wblock.filterUpdatePopup.state"
    private static let startedAtKey = "wblock.filterUpdatePopup.startedAt"
    private static let finishedAtKey = "wblock.filterUpdatePopup.finishedAt"
    private static let checkedFiltersKey = "wblock.filterUpdatePopup.checkedFilters"
    private static let updatedFiltersKey = "wblock.filterUpdatePopup.updatedFilters"
    private static let errorKey = "wblock.filterUpdatePopup.error"
    private static let staleAfter: TimeInterval = 300
    private static let lock = NSLock()

    public static func beginIfIdle(
        groupIdentifier: String = GroupIdentifier.shared.value,
        now: Date = Date()
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return false }
        let current = snapshot(unlockedDefaults: defaults, now: now)
        guard current.state != .running else { return false }
        defaults.set(State.running.rawValue, forKey: stateKey)
        defaults.set(now.timeIntervalSince1970, forKey: startedAtKey)
        defaults.removeObject(forKey: finishedAtKey)
        defaults.set(0, forKey: checkedFiltersKey)
        defaults.set(0, forKey: updatedFiltersKey)
        defaults.removeObject(forKey: errorKey)
        defaults.synchronize()
        return true
    }

    public static func snapshot(
        groupIdentifier: String = GroupIdentifier.shared.value,
        now: Date = Date()
    ) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else {
            return Snapshot(state: .failed, startedAt: nil, finishedAt: nil, checkedFilters: 0, updatedFilters: 0, error: "Shared update status is unavailable.")
        }
        return snapshot(unlockedDefaults: defaults, now: now)
    }

    public static func finish(
        _ outcome: SharedAutoUpdateManager.AutoUpdateRunOutcome,
        groupIdentifier: String = GroupIdentifier.shared.value,
        now: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return }

        let state: State
        let checkedFilters: Int
        let updatedFilters: Int
        let error: String?
        switch outcome {
        case .completed(let completion):
            checkedFilters = completion.checkedFilters
            updatedFilters = completion.updatedFilters
            error = nil
            state = completion.result == .noFilterUpdates || completion.result == .noSelectedFilters
                ? .noChange
                : .succeeded
        case .failed(let message):
            state = .failed
            checkedFilters = 0
            updatedFilters = 0
            error = message
        case .deferred(let phase):
            state = .failed
            checkedFilters = 0
            updatedFilters = 0
            error = "Update deferred during \(phase)."
        case .cancelled:
            state = .failed
            checkedFilters = 0
            updatedFilters = 0
            error = "Update was cancelled."
        case .skipped(let reason):
            state = .failed
            checkedFilters = 0
            updatedFilters = 0
            error = "Update skipped: \(reason)."
        }

        defaults.set(state.rawValue, forKey: stateKey)
        defaults.set(now.timeIntervalSince1970, forKey: finishedAtKey)
        defaults.set(checkedFilters, forKey: checkedFiltersKey)
        defaults.set(updatedFilters, forKey: updatedFiltersKey)
        if let error {
            defaults.set(error, forKey: errorKey)
        } else {
            defaults.removeObject(forKey: errorKey)
        }
        defaults.synchronize()
    }

    private static func snapshot(unlockedDefaults defaults: UserDefaults, now: Date) -> Snapshot {
        let rawState = defaults.string(forKey: stateKey) ?? State.idle.rawValue
        var state = State(rawValue: rawState) ?? .idle
        let startedAt = defaults.object(forKey: startedAtKey) as? Double
        let finishedAt = defaults.object(forKey: finishedAtKey) as? Double
        if state == .running,
           let startedAt,
           now.timeIntervalSince1970 - startedAt > staleAfter {
            state = .failed
        }
        return Snapshot(
            state: state,
            startedAt: startedAt,
            finishedAt: finishedAt,
            checkedFilters: max(0, defaults.integer(forKey: checkedFiltersKey)),
            updatedFilters: max(0, defaults.integer(forKey: updatedFiltersKey)),
            error: defaults.string(forKey: errorKey)
        )
    }
}
