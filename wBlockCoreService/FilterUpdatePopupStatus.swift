import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// App-group backed lifecycle state for the Safari popup's headless filter update.
/// The updater remains owned by SharedAutoUpdateManager; this store only exposes a
/// small, restart-safe status contract to the extension UI.
public enum FilterUpdatePopupStatus {
    public struct ClaimToken: RawRepresentable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        fileprivate static func fresh() -> Self {
            Self(rawValue: UUID().uuidString)
        }
    }

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
    private static let requestKey = "wblock.filterUpdatePopup.requested"
    private static let ownerTokenKey = "wblock.filterUpdatePopup.ownerToken"
    public static let requestNotificationName = "skula.wBlock.filter-update-requested"
    private static let staleAfter: TimeInterval = 300
    private static let lock = NSLock()
    private static let lockFilename = "filter-update-popup.lock"

    public static func beginIfIdle(
        groupIdentifier: String = GroupIdentifier.shared.value,
        now: Date = Date(),
        lockDirectory: URL? = nil
    ) -> ClaimToken? {
        withStateLock(groupIdentifier: groupIdentifier, lockDirectory: lockDirectory) {
            guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return nil }
            defaults.synchronize()
            return claimIfIdle(unlockedDefaults: defaults, now: now)
        } ?? nil
    }

    private static func claimIfIdle(
        unlockedDefaults defaults: UserDefaults,
        now: Date
    ) -> ClaimToken? {
        let current = snapshot(unlockedDefaults: defaults, now: now)
        guard current.state != .running else { return nil }
        let token = ClaimToken.fresh()
        defaults.set(State.running.rawValue, forKey: stateKey)
        defaults.set(token.rawValue, forKey: ownerTokenKey)
        // A fresh direct/XPC claim must never inherit an unconsumed app request
        // from an older timed-out generation.
        defaults.set(false, forKey: requestKey)
        defaults.set(now.timeIntervalSince1970, forKey: startedAtKey)
        defaults.removeObject(forKey: finishedAtKey)
        defaults.set(0, forKey: checkedFiltersKey)
        defaults.set(0, forKey: updatedFiltersKey)
        defaults.removeObject(forKey: errorKey)
        defaults.synchronize()
        return token
    }

    /// Asks a resident containing app to run the update without activating it.
    @discardableResult
    public static func requestUpdate(
        groupIdentifier: String = GroupIdentifier.shared.value,
        now: Date = Date(),
        lockDirectory: URL? = nil
    ) -> ClaimToken? {
        let token: ClaimToken? = withStateLock(groupIdentifier: groupIdentifier, lockDirectory: lockDirectory) {
            guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return nil }
            defaults.synchronize()
            guard let token = claimIfIdle(unlockedDefaults: defaults, now: now) else { return nil }
            defaults.set(true, forKey: requestKey)
            defaults.synchronize()
            return token
        } ?? nil
        guard token != nil else { return nil }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: requestNotificationName as CFString),
            nil,
            nil,
            true
        )
        return token
    }

    public static func consumeUpdateRequest(
        groupIdentifier: String = GroupIdentifier.shared.value,
        lockDirectory: URL? = nil
    ) -> ClaimToken? {
        withStateLock(groupIdentifier: groupIdentifier, lockDirectory: lockDirectory) {
            guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return nil }
            defaults.synchronize()
            guard defaults.bool(forKey: requestKey),
                  defaults.string(forKey: stateKey) == State.running.rawValue,
                  let rawToken = defaults.string(forKey: ownerTokenKey),
                  !rawToken.isEmpty
            else { return nil }
            defaults.set(false, forKey: requestKey)
            defaults.synchronize()
            return ClaimToken(rawValue: rawToken)
        } ?? nil
    }

    public static func snapshot(
        groupIdentifier: String = GroupIdentifier.shared.value,
        now: Date = Date(),
        lockDirectory: URL? = nil
    ) -> Snapshot {
        withStateLock(groupIdentifier: groupIdentifier, lockDirectory: lockDirectory) {
            guard let defaults = UserDefaults(suiteName: groupIdentifier) else {
                return Snapshot(state: .failed, startedAt: nil, finishedAt: nil, checkedFilters: 0, updatedFilters: 0, error: String(localized: "Shared update status is unavailable.", comment: "Filter update popup shared-state error"))
            }
            defaults.synchronize()
            return snapshot(unlockedDefaults: defaults, now: now)
        } ?? Snapshot(state: .failed, startedAt: nil, finishedAt: nil, checkedFilters: 0, updatedFilters: 0, error: String(localized: "Shared update status lock is unavailable.", comment: "Filter update popup shared-state lock error"))
    }


    /// Returns the current status and acknowledges a terminal result. The popup keeps
    /// the returned value in its DOM, while the next popup session starts clean.
    public static func consumeSnapshot(
        groupIdentifier: String = GroupIdentifier.shared.value,
        now: Date = Date(),
        lockDirectory: URL? = nil
    ) -> Snapshot {
        withStateLock(groupIdentifier: groupIdentifier, lockDirectory: lockDirectory) {
            guard let defaults = UserDefaults(suiteName: groupIdentifier) else {
                return Snapshot(state: .failed, startedAt: nil, finishedAt: nil, checkedFilters: 0, updatedFilters: 0, error: String(localized: "Shared update status is unavailable.", comment: "Filter update popup shared-state error"))
            }
            defaults.synchronize()

            let current = snapshot(unlockedDefaults: defaults, now: now)
            guard current.state != .idle, current.state != .running else { return current }
            [stateKey, ownerTokenKey, requestKey, startedAtKey, finishedAtKey, checkedFiltersKey, updatedFiltersKey, errorKey]
                .forEach(defaults.removeObject(forKey:))
            defaults.synchronize()
            return current
        } ?? Snapshot(state: .failed, startedAt: nil, finishedAt: nil, checkedFilters: 0, updatedFilters: 0, error: String(localized: "Shared update status lock is unavailable.", comment: "Filter update popup shared-state lock error"))
    }

    @discardableResult
    public static func finish(
        _ outcome: SharedAutoUpdateManager.AutoUpdateRunOutcome,
        claim: ClaimToken,
        groupIdentifier: String = GroupIdentifier.shared.value,
        now: Date = Date(),
        lockDirectory: URL? = nil
    ) -> Bool {
        withStateLock(groupIdentifier: groupIdentifier, lockDirectory: lockDirectory) {
            guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return false }
            defaults.synchronize()
            guard defaults.string(forKey: ownerTokenKey) == claim.rawValue,
                  defaults.string(forKey: stateKey) == State.running.rawValue
            else { return false }

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
            defaults.set(false, forKey: requestKey)
            defaults.set(now.timeIntervalSince1970, forKey: finishedAtKey)
            defaults.set(checkedFilters, forKey: checkedFiltersKey)
            defaults.set(updatedFilters, forKey: updatedFiltersKey)
            if let error {
                defaults.set(error, forKey: errorKey)
            } else {
                defaults.removeObject(forKey: errorKey)
            }
            defaults.synchronize()
            return true
        } ?? false
    }

    private static func withStateLock<T>(
        groupIdentifier: String,
        lockDirectory: URL?,
        _ operation: () -> T
    ) -> T? {
        lock.lock()
        defer { lock.unlock() }

        #if canImport(Darwin)
        let directory = lockDirectory
            ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
        guard let directory else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let lockURL = directory.appendingPathComponent(lockFilename, isDirectory: false)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return nil }
        defer { _ = flock(descriptor, LOCK_UN) }
        return operation()
        #else
        return operation()
        #endif
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
