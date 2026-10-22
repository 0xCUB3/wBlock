import Foundation
import wBlockCoreService

enum FilterContextMenuAction: String {
    case info
    case settings
    case download
    case viewRules
    case editRules
    case editInfo
    case fallbacks
    case deleteList
}

enum UserScriptContextMenuAction: String {
    case info
    case settings
    case viewContent
    case editContent
    case editInfo
    case matchPatterns
    case download
    case deleteScript
}

enum ContextMenuActionAvailability {
    static func filterActions(for filter: FilterList, isDownloaded: Bool) -> [FilterContextMenuAction] {
        var actions: [FilterContextMenuAction] = [.info]
        if filter.isRemoteURL && !isDownloaded { actions.append(.download) }
        // Settings only once there is something to configure (#1028).
        if isDownloaded || filter.isInlineUserList {
            actions += [.settings, filter.isInlineUserList ? .editRules : .viewRules]
        }
        if filter.isCustom {
            actions.append(.editInfo)
            actions.append(.deleteList)
        }
        return actions
    }

    static func userScriptActions(
        isBuiltIn: Bool,
        isLocal: Bool,
        isDownloaded: Bool
    ) -> [UserScriptContextMenuAction] {
        var actions: [UserScriptContextMenuAction] = [.info]
        if !isLocal && !isDownloaded { actions.append(.download) }
        if isDownloaded {
            // URL-sourced content remains read-only because updates replace it.
            actions += [.settings, !isBuiltIn && isLocal ? .editContent : .viewContent]
        }
        if !isBuiltIn { actions += [.editInfo, .deleteScript] }
        return actions
    }
}
