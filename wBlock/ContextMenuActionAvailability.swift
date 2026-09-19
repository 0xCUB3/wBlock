import Foundation
import wBlockCoreService

enum FilterContextMenuAction: String {
    case info
    case settings
    case viewRules
    case editRules
    case editInfo
    case moveTo
    case deleteList
}

enum UserScriptContextMenuAction: String {
    case info
    case settings
    case viewContent
    case editContent
    case editInfo
    case download
    case moveTo
    case deleteScript
}

enum ContextMenuActionAvailability {
    static func filterActions(for filter: FilterList, isDownloaded: Bool) -> [FilterContextMenuAction] {
        var actions: [FilterContextMenuAction] = [.info, .settings]
        if isDownloaded || filter.isInlineUserList {
            actions.append(filter.isInlineUserList ? .editRules : .viewRules)
        }
        if filter.isCustom {
            if filter.category != .foreign { actions.append(.moveTo) }
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
        var actions: [UserScriptContextMenuAction] = [.info, .settings]
        if !isLocal && !isDownloaded { actions.append(.download) }
        if isDownloaded {
            // URL-sourced content remains read-only because updates replace it.
            actions.append(!isBuiltIn && isLocal ? .editContent : .viewContent)
        }
        if !isBuiltIn { actions += [.editInfo, .moveTo, .deleteScript] }
        return actions
    }
}
