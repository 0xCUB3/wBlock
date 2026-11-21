//
//  BlockingPauseStore.swift
//  wBlockCoreService
//
//  Stores the global "blocking paused" flag in the shared app-group container so that
//  the host app and the FilterUpdateAgent/XPC helpers share one source of truth.
//

import Foundation
import CoreFoundation

public struct BlockingPauseComponents: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let filters = BlockingPauseComponents(rawValue: 1 << 0)
    public static let userScripts = BlockingPauseComponents(rawValue: 1 << 1)
    public static let elementZapper = BlockingPauseComponents(rawValue: 1 << 2)
    public static let all: BlockingPauseComponents = [.filters, .userScripts, .elementZapper]
}

public enum BlockingPauseStore {
    /// Legacy UserDefaults key backing the single paused flag.
    public static let key = "isBlockingPaused"
    /// App-group key storing the bitmask of independently paused components.
    public static let componentsKey = "blockingPausedComponents"
    /// Shared request key used by the extension to ask the containing app to resume.
    public static let resumeRequestKey = "blockingResumeRequested"
    public static let resumeStatusKey = "blockingResumeStatus"
    public static let resumeErrorKey = "blockingResumeError"
    /// Time of the last resume progress (request queued, or apply heartbeat). An in-flight
    /// status older than `resumeTimeout` reads as failed.
    public static let resumeRequestedAtKey = "blockingResumeRequestedAt"
    /// Epoch time until which content blockers read rules as unpaused. Set only for the
    /// reload inside a resume, so the persisted pause flags are never touched.
    public static let contentBlockingResumingUntilKey = "contentBlockingResumingUntil"
    /// Seconds a resume may go without progress before it reads as failed. The same value
    /// bounds the reload window, so a crash mid-resume unpauses content blockers only briefly.
    public static let resumeTimeout: TimeInterval = 120
    public static let resumeRequestNotificationName = "skula.wBlock.blocking-resume-requested"
    private static let resumeRequestLock = NSLock()

    public enum ResumeStatus: String {
        case idle
        case pending
        case applying
        case succeeded
        case failed
    }

    /// Reads the paused components, migrating the old single Boolean to all components.
    public static func pausedComponents(
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> BlockingPauseComponents {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return [] }
        let stored: BlockingPauseComponents
        if let rawValue = defaults.object(forKey: componentsKey) as? NSNumber {
            stored = BlockingPauseComponents(rawValue: rawValue.intValue).intersection(.all)
        } else {
            // Existing installations only have `isBlockingPaused`; a true value means that
            // every component was paused by the old global switch.
            stored = defaults.bool(forKey: key) ? BlockingPauseComponents.all : []
            defaults.set(stored.rawValue, forKey: componentsKey)
        }
        // While a resume reload is open, filters and the zapper read as unpaused. This is
        // applied on read only; the stored components are never changed here.
        return resumeWindowOpen(defaults) ? stored.subtracting([.filters, .elementZapper]) : stored
    }

    public static func isPaused(
        _ component: BlockingPauseComponents,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> Bool {
        !pausedComponents(groupIdentifier: groupIdentifier).intersection(component).isEmpty
    }

    /// True when both output-producing blocking components are paused. User scripts are
    /// independent and do not make the content-blocker extensions inert.
    public static func isContentBlockingPaused(
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> Bool {
        isPaused(.filters, groupIdentifier: groupIdentifier)
            && isPaused(.elementZapper, groupIdentifier: groupIdentifier)
    }

    private static func resumeWindowOpen(_ defaults: UserDefaults) -> Bool {
        defaults.double(forKey: contentBlockingResumingUntilKey) > Date().timeIntervalSince1970
    }

    /// Reads the global paused state. It remains true whenever any component is paused.
    public static func isPaused(groupIdentifier: String = GroupIdentifier.shared.value) -> Bool {
        !pausedComponents(groupIdentifier: groupIdentifier).isEmpty
    }

    public static func setPausedComponents(
        _ components: BlockingPauseComponents,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) {
        let normalized = components.intersection(.all)
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return }
        defaults.set(normalized.rawValue, forKey: componentsKey)
        defaults.set(!normalized.isEmpty, forKey: key)
    }

    /// Persists the legacy global operation: pausing selects all components and resuming
    /// clears every component selection.
    public static func setPaused(
        _ paused: Bool,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) {
        setPausedComponents(paused ? .all : [], groupIdentifier: groupIdentifier)
    }

    /// Lets Safari read the prepared rules during a serialized resume reload. It opens a
    /// transient window instead of editing the persisted pause flags, so a crash mid-resume
    /// leaves the flags paused and the window expires on its own.
    @MainActor
    public static func withContentBlockingResumed<T>(
        groupIdentifier: String = GroupIdentifier.shared.value,
        operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        _ = pausedComponents(groupIdentifier: groupIdentifier)
        let defaults = UserDefaults(suiteName: groupIdentifier)
        defaults?.set(Date().timeIntervalSince1970 + resumeTimeout, forKey: contentBlockingResumingUntilKey)
        defer { defaults?.removeObject(forKey: contentBlockingResumingUntilKey) }
        return try await operation()
    }

    /// Requests that the containing app run its canonical resume/apply lifecycle.
    /// Pending and applying requests are coalesced so repeated popup taps cannot start
    /// another apply or reset the status of the request already in progress.
    @discardableResult
    public static func requestResume(groupIdentifier: String = GroupIdentifier.shared.value) -> ResumeStatus {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return .idle }
        resumeRequestLock.lock()
        defer { resumeRequestLock.unlock() }
        // A stale in-flight status reads as failed here, so a fresh request goes through.
        let currentStatus = resumeStatus(groupIdentifier: groupIdentifier).status
        if currentStatus == .pending || currentStatus == .applying {
            return currentStatus
        }

        defaults.set(true, forKey: resumeRequestKey)
        defaults.set(ResumeStatus.pending.rawValue, forKey: resumeStatusKey)
        defaults.set(Date().timeIntervalSince1970, forKey: resumeRequestedAtKey)
        defaults.removeObject(forKey: resumeErrorKey)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: resumeRequestNotificationName as CFString),
            nil,
            nil,
            true
        )
        return .pending
    }

    /// Consumes one queued resume request. This is intentionally separate from `setPaused`:
    /// the app must clear the pause only through AppFilterManager.setBlockingPaused(false).
    public static func consumeResumeRequest(groupIdentifier: String = GroupIdentifier.shared.value) -> Bool {
        guard let defaults = UserDefaults(suiteName: groupIdentifier),
              defaults.bool(forKey: resumeRequestKey)
        else { return false }
        defaults.set(false, forKey: resumeRequestKey)
        return true
    }

    /// Also serves as the apply heartbeat: each call restarts the staleness clock.
    public static func setResumeApplying(groupIdentifier: String = GroupIdentifier.shared.value) {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return }
        defaults.set(ResumeStatus.applying.rawValue, forKey: resumeStatusKey)
        defaults.set(Date().timeIntervalSince1970, forKey: resumeRequestedAtKey)
    }

    public static func setResumeSucceeded(groupIdentifier: String = GroupIdentifier.shared.value) {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return }
        defaults.set(ResumeStatus.succeeded.rawValue, forKey: resumeStatusKey)
        defaults.removeObject(forKey: resumeErrorKey)
    }

    public static func setResumeFailed(
        _ error: String,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return }
        defaults.set(ResumeStatus.failed.rawValue, forKey: resumeStatusKey)
        defaults.set(error, forKey: resumeErrorKey)
    }

    public static func resumeStatus(
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> (status: ResumeStatus, error: String?) {
        let defaults = UserDefaults(suiteName: groupIdentifier)
        let rawStatus = defaults?.string(forKey: resumeStatusKey) ?? ResumeStatus.idle.rawValue
        let status = ResumeStatus(rawValue: rawStatus) ?? .idle
        let lastProgress = defaults?.double(forKey: resumeRequestedAtKey) ?? 0
        let inFlight = status == .pending || status == .applying
        if inFlight && Date().timeIntervalSince1970 - lastProgress > resumeTimeout {
            return (
                status: .failed,
                error: NSLocalizedString(
                    "Resuming blocking timed out. Try again.",
                    comment: "Popup message when a resume made no progress for two minutes"
                )
            )
        }
        return (status: status, error: defaults?.string(forKey: resumeErrorKey))
    }
}
