import Foundation
import SwiftUI
import wBlockCoreService

/// The complete, ordered badge matrix shared by the metadata-only Info views.
enum InfoBadgeKind: Equatable {
    case builtIn
    case custom
    case localImport
    case downloaded
    case notDownloaded
    case enabled
    case disabled
}

struct InfoBadgeView: View {
    let kind: InfoBadgeKind

    var body: some View {
        switch kind {
        case .builtIn:
            Badge(text: "Built-in", color: .orange)
        case .custom:
            Badge(text: "Custom", color: .blue)
        case .localImport:
            Badge(text: "Local Import", color: .blue)
        case .downloaded:
            Badge(text: "Downloaded", color: .green)
        case .notDownloaded:
            Badge(text: "Not Downloaded", color: .red)
        case .enabled:
            Badge(text: "Enabled", color: .green)
        case .disabled:
            Badge(text: "Disabled", color: .secondary)
        }
    }
}

enum InfoBadgeSupport {
    static func filterBadges(_ filter: FilterList, isDownloaded: Bool? = nil) -> [InfoBadgeKind] {
        var badges: [InfoBadgeKind] = []
        if filter.isInlineUserList {
            badges.append(.localImport)
        } else if filter.isCustom {
            badges.append(.custom)
        } else {
            badges.append(.builtIn)
        }
        badges.append(filter.isSelected ? .enabled : .disabled)
        if isDownloaded ?? (filter.sourceRuleCount != nil) {
            badges.append(.downloaded)
        } else if isRemote(filter.url) {
            badges.append(.notDownloaded)
        }
        return badges
    }

    static func userScriptBadges(
        _ script: UserScript,
        isDownloaded: Bool,
        isBuiltIn: Bool
    ) -> [InfoBadgeKind] {
        var badges: [InfoBadgeKind] = []
        if isBuiltIn {
            badges.append(.builtIn)
        } else if script.isLocal {
            badges.append(.localImport)
        } else {
            badges.append(.custom)
        }
        badges.append(script.isEnabled ? .enabled : .disabled)
        if isDownloaded {
            badges.append(.downloaded)
        } else if !script.isLocal {
            badges.append(.notDownloaded)
        }
        return badges
    }

    private static func isRemote(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}
