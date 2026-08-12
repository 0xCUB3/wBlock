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
    public static let resumeRequestNotificationName = "skula.wBlock.blocking-resume-requested"

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
        UserDefaults(suiteName: groupIdentifier)?.set(true, forKey: resumeRequestKey)
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
}
