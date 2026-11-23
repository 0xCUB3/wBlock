import Foundation
import SwiftUI
import wBlockCoreService

/// Pure presentation mode for wBlock (#404).
///
/// Stored device-locally in `UserDefaults.standard` (never in the shared app
/// group, iCloud Sync payload, or local backups). Switching modes never mutates
/// filter lists or userscripts.
enum AppMode: String, CaseIterable, Identifiable, Sendable {
    /// Default streamlined layout; raw value stays `"basic"` for stored
    /// preference compatibility.
    case basic
    /// Full filter-list and userscript layout ("Show All Lists").
    case advanced

    static let storageKey = "wBlock.appMode"

    var id: String { rawValue }

    /// True when the install has custom filter lists or user-added scripts
    /// that require Advanced mode to manage directly.
    @MainActor
    static func detectCustomContent() -> Bool {
        if ProtobufDataManager.shared.getFilterLists().contains(where: \.isCustom) {
            return true
        }
        return UserScriptManager.shared.userScripts.contains {
            UserScriptManager.shared.builtInTier(for: $0) == nil
        }
    }

    /// Persists the initial default once if no explicit choice has been stored yet.
    /// Existing installs with custom lists or user-added scripts stay in `.advanced`;
    /// everyone else starts in Standard (`.basic`).
    @discardableResult
    static func seedIfNeeded(
        hasCompletedOnboarding: Bool,
        hasCustomContent: Bool = false,
        defaults: UserDefaults = .standard
    ) -> AppMode {
        if let raw = defaults.string(forKey: storageKey),
           let stored = AppMode(rawValue: raw) {
            return stored
        }
        let resolved: AppMode = (hasCompletedOnboarding && hasCustomContent) ? .advanced : .basic
        defaults.set(resolved.rawValue, forKey: storageKey)
        return resolved
    }
}
