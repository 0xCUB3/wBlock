//
//  GroupIdentifier.swift
//  safari-blocker
//
//  Created by Andrey Meshkov on 01/02/2025.
//

import Foundation
#if os(macOS)
import Security
#endif

/// GroupIdentifier provides access to the app group identifier used for sharing
/// data between the main app and its extensions.
///
/// This class implements the singleton pattern to ensure consistent access to
/// the app group identifier throughout the application. The group identifier is
/// used to access the shared container where content blocker rules are stored.
public final class GroupIdentifier: Sendable {
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
    /// Direct-distribution builds add the team-prefixed app group at signing
    /// time. Prefer the signed entitlement so helper tools without a patchable
    /// Info.plist still use the same container as the main app.
    private init() {
        #if os(macOS)
        if let entitledGroup = Self.teamPrefixedAppGroupFromEntitlements() {
            value = entitledGroup
        } else if let prefix = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String {
            value = "\(prefix)group.skula.wBlock"
        } else {
            value = "group.skula.wBlock"
        }
        #else
        value = "group.skula.wBlock"
        #endif
    }

    #if os(macOS)
    private static func teamPrefixedAppGroupFromEntitlements() -> String? {
        guard let task = SecTaskCreateFromSelf(nil),
              let entitlementValue = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.application-groups" as CFString,
                nil
              )
        else {
            return nil
        }

        let groups: [String]
        if let swiftGroups = entitlementValue as? [String] {
            groups = swiftGroups
        } else if let array = entitlementValue as? NSArray {
            groups = array.compactMap { $0 as? String }
        } else {
            groups = []
        }

        return groups.first {
            $0 != "group.skula.wBlock" && $0.hasSuffix(".group.skula.wBlock")
        }
    }
    #endif
}
