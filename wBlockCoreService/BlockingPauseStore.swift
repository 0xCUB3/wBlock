//
//  BlockingPauseStore.swift
//  wBlockCoreService
//
//  Stores the global "blocking paused" flag in the shared app-group container so that
//  the host app and the FilterUpdateAgent/XPC helpers share one source of truth.
//

import Foundation
import CoreFoundation

public enum BlockingPauseStore {
    /// User defaults key backing the paused flag.
    public static let key = "isBlockingPaused"
    /// Shared request key used by the extension to ask the containing app to resume.
    public static let resumeRequestKey = "blockingResumeRequested"
    public static let resumeStatusKey = "blockingResumeStatus"
    public static let resumeErrorKey = "blockingResumeError"
    public static let resumeRequestNotificationName = "skula.wBlock.blocking-resume-requested"

    public enum ResumeStatus: String {
        case idle
        case pending
        case applying
        case succeeded
        case failed
    }

    /// Reads the paused flag from the shared app-group container.
    public static func isPaused(groupIdentifier: String = GroupIdentifier.shared.value) -> Bool {
        UserDefaults(suiteName: groupIdentifier)?.bool(forKey: key) ?? false
    }

    /// Persists the paused flag to the shared app-group container.
    public static func setPaused(
        _ paused: Bool,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) {
        UserDefaults(suiteName: groupIdentifier)?.set(paused, forKey: key)
    }

    /// Requests that the containing app run its canonical resume/apply lifecycle.
    public static func requestResume(groupIdentifier: String = GroupIdentifier.shared.value) {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return }
        defaults.set(true, forKey: resumeRequestKey)
        defaults.set(ResumeStatus.pending.rawValue, forKey: resumeStatusKey)
        defaults.removeObject(forKey: resumeErrorKey)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: resumeRequestNotificationName as CFString),
            nil,
            nil,
            true
        )
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

    public static func setResumeApplying(groupIdentifier: String = GroupIdentifier.shared.value) {
        UserDefaults(suiteName: groupIdentifier)?.set(ResumeStatus.applying.rawValue, forKey: resumeStatusKey)
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
        return (
            status: ResumeStatus(rawValue: rawStatus) ?? .idle,
            error: defaults?.string(forKey: resumeErrorKey)
        )
    }
}
