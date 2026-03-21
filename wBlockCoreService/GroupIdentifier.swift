//
//  GroupIdentifier.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 01/02/2025.
//

import Foundation

/// GroupIdentifier provides access to the app group identifier used for sharing
/// data between the main app and its extensions.
///
/// This class implements the singleton pattern to ensure consistent access to
/// the app group identifier throughout the application. The group identifier is
/// used to access the shared container where content blocker rules are stored.
public final class GroupIdentifier {
    /// Shared singleton instance of GroupIdentifier.
    public static let shared = GroupIdentifier()

    /// The app group identifier string used to access the shared container.
    public let value: String

    /// Private initializer that sets the appropriate group identifier based on
    /// platform and distribution method.
    ///
    /// On macOS Sequoia, non-Mac App Store apps that access a group container
    /// using the `group.` prefix trigger a "would like to access data from
    /// other apps" TCC prompt. Using the `<TeamID>.group.` prefix avoids this.
    ///
    /// MAS builds don't set AppIdentifierPrefix in the Info.plist, so they
    /// fall through to the plain identifier (which is exempt from the prompt).
    /// Direct distribution builds have AppIdentifierPrefix patched in by the
    /// build script, so they use the team-prefixed identifier.
    private init() {
        #if os(macOS)
        if let prefix = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String {
            value = "\(prefix)group.skula.wBlock"
        } else {
            value = "group.skula.wBlock"
        }
        #else
        value = "group.skula.wBlock"
        #endif
    }
}
