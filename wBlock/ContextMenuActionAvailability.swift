import Foundation
import wBlockCoreService

enum FilterContextMenuAction: String {
    case info
    case viewRules
    case editRules
    case deleteList
}

enum UserScriptContextMenuAction: String {
    case info
    case viewContent
    case editContent
    case deleteScript
}

enum ContextMenuActionAvailability {
    static func filterActions(for filter: FilterList) -> [FilterContextMenuAction] {
        guard filter.isCustom else { return [.info, .viewRules] }
        if filter.isInlineUserList {
            return [.info, .editRules, .deleteList]
        }
        // A URL-imported custom list can be inspected or removed, but not edited.
        return [.info, .viewRules, .deleteList]
    }

    static func userScriptActions(isBuiltIn: Bool, isLocal: Bool) -> [UserScriptContextMenuAction] {
        guard !isBuiltIn else { return [.info, .viewContent] }
        if isLocal {
            return [.info, .editContent, .deleteScript]
        }
        // A URL-imported custom script is view-only with respect to its source.
        return [.info, .viewContent, .deleteScript]
    }
}
