//
//  BlockingPauseStore.swift
//  wBlockCoreService
//
//  Stores the global "blocking paused" flag in the shared app-group container so that
//  the host app and the FilterUpdateAgent/XPC helpers share one source of truth.
//

import Foundation

public enum BlockingPauseStore {
    /// User defaults key backing the paused flag.
    public static let key = "isBlockingPaused"

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
}
