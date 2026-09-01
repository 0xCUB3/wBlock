import Foundation
import SwiftUI
import wBlockCoreService

/// The complete, ordered badge matrix shared by the metadata-only Info views.
enum InfoBadgeKind: Equatable {
    case filters
    case userscript
    case userstyle
    case integrated
    case builtIn
    case custom
    case localImport
    case downloaded
    case notDownloaded
    case enabled
    case disabled
    case version(String)
}

struct InfoBadgeView: View {
    let kind: InfoBadgeKind

    var body: some View {
        switch kind {
        case .filters:
            Badge(text: "Filters", color: .red)
        case .userscript:
            Badge(text: "Userscript", color: .red)
        case .userstyle:
            Badge(text: "Userstyle", color: .purple)
        case .integrated:
            Badge(text: "Integrated", color: .red)
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
        case .version(let version):
            Badge(
                text: LocalizedStrings.format(
                    "v%@",
                    comment: "Userscript version badge",
                    version
                ),
                color: .blue
            )
        }
    }
}

enum InfoBadgeSupport {
    static func filterBadges(_ filter: FilterList) -> [InfoBadgeKind] {
        var badges: [InfoBadgeKind] = [.filters]
        if filter.isInlineUserList {
            badges.append(.localImport)
        } else if filter.isCustom {
            badges.append(.custom)
        } else {
            badges.append(.builtIn)
        }
        badges.append(filter.isSelected ? .enabled : .disabled)
        if filter.sourceRuleCount != nil {
            badges.append(.downloaded)
        } else if isRemote(filter.url), filter.isCustom, !filter.isSelected {
            badges.append(.notDownloaded)
        }
        return badges
    }

    static func userScriptBadges(
        _ script: UserScript,
        isDownloaded: Bool,
        isBuiltIn: Bool,
        isIntegrated: Bool
    ) -> [InfoBadgeKind] {
        var badges: [InfoBadgeKind] = [script.isUserStyle ? .userstyle : .userscript]
        if isIntegrated {
            badges[0] = .integrated
        }
        if isBuiltIn {
            badges.append(.builtIn)
        } else if script.isLocal {
            badges.append(.localImport)
        } else {
            badges.append(.custom)
        }
        if !script.version.isEmpty {
            badges.append(.version(script.version))
        }
        badges.append(script.isEnabled ? .enabled : .disabled)
        if !isDownloaded, !script.isLocal {
            badges.append(.notDownloaded)
        }
        return badges
    }

    private static func isRemote(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}
