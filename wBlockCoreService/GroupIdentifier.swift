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
    /// The direct-distribution build signs each bundle with both the plain and
    /// team-prefixed app group. Helpers embedded as plain executables do not
    /// have a patchable Info.plist on disk, so the signing entitlements are the
    /// source of truth when choosing the runtime group identifier.
    private init() {
        #if os(macOS)
        value = Self.resolvedMacOSGroupIdentifier()
        #else
        value = Self.baseGroupIdentifier
        #endif
    }

    private static let baseGroupIdentifier = "group.skula.wBlock"

    #if os(macOS)
    private static func resolvedMacOSGroupIdentifier() -> String {
        if let identifier = teamPrefixedApplicationGroupFromSigningEntitlements() {
            return identifier
        }

        if let prefix = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String,
           let identifier = applicationGroupIdentifier(withAppIdentifierPrefix: prefix) {
            return identifier
        }

        return baseGroupIdentifier
    }

    private static func applicationGroupIdentifier(withAppIdentifierPrefix prefix: String) -> String? {
        guard !prefix.isEmpty, !prefix.contains("$(") else { return nil }
        if prefix.hasSuffix(".") {
            return "\(prefix)\(baseGroupIdentifier)"
        }
        return "\(prefix).\(baseGroupIdentifier)"
    }

    private static func teamPrefixedApplicationGroupFromSigningEntitlements() -> String? {
        guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault),
              let entitlement = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.application-groups" as CFString,
                nil
              ),
              let applicationGroups = entitlement as? [String]
        else {
            return nil
        }

        let teamPrefixedSuffix = ".\(baseGroupIdentifier)"
        return applicationGroups.first { $0.hasSuffix(teamPrefixedSuffix) }
    }
    #endif
}
