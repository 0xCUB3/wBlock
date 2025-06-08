//
//  GroupIdentifier.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 01/02/2025.
//

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
    /// platform.
    ///
    /// Before XCode 16.3 it was necessary to have different group identifiers
    /// for macOS and iOS and have something like this:
    ///
    /// ```swift
    /// if let teamIdentifierPrefix = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String
    ///     value = "\(teamIdentifierPrefix)group.dev.ameshkov.safari-blocker"
    /// }
    /// ```
    ///
    /// Starting from XCode 16.3 this is no longer necessary and we can use the
    /// same group ID for iOS and macOS.
    private init() {
        value = "group.skula.wBlock"
    }
}
