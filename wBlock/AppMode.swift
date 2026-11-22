import Foundation
import SwiftUI

/// Pure presentation mode for wBlock (#404).
///
/// Stored device-locally in `UserDefaults.standard` (never in the shared app
/// group, iCloud Sync payload, or local backups). Switching modes never mutates
/// filter lists or userscripts.
enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case basic
    case advanced

    static let storageKey = "wBlock.appMode"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .basic: "Basic"
        case .advanced: "Advanced"
        }
    }

    var localizedTitle: String {
        switch self {
        case .basic: NSLocalizedString("Basic", comment: "App mode")
        case .advanced: NSLocalizedString("Advanced", comment: "App mode")
        }
    }

    /// Resolves the mode without writing to `defaults`.
    /// Existing installs that completed onboarding before Basic mode existed
    /// default to `.advanced`; fresh installs default to `.basic`.
    static func resolved(
        hasCompletedOnboarding: Bool,
        defaults: UserDefaults = .standard
    ) -> AppMode {
        if let raw = defaults.string(forKey: storageKey),
           let stored = AppMode(rawValue: raw) {
            return stored
        }
        return hasCompletedOnboarding ? .advanced : .basic
    }

    /// Persists the initial default once if no explicit choice has been stored yet.
    @discardableResult
    static func seedIfNeeded(
        hasCompletedOnboarding: Bool,
        defaults: UserDefaults = .standard
    ) -> AppMode {
        if let raw = defaults.string(forKey: storageKey),
           let stored = AppMode(rawValue: raw) {
            return stored
        }
        let resolved: AppMode = hasCompletedOnboarding ? .advanced : .basic
        defaults.set(resolved.rawValue, forKey: storageKey)
        return resolved
    }
}
