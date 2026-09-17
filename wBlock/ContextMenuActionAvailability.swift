import Foundation
import wBlockCoreService

enum FilterContextMenuAction: String {
    case info
    case settings
    case viewRules
    case editRules
    case editInfo
    case deleteList
}

enum UserScriptContextMenuAction: String {
    case info
    case settings
    case viewContent
    case editContent
    case editInfo
    case download
    case deleteScript
}

enum ContextMenuActionAvailability {
    static func filterActions(for filter: FilterList) -> [FilterContextMenuAction] {
        guard filter.isCustom else { return [.info, .settings, .viewRules] }
        if filter.isInlineUserList {
            return [.info, .settings, .editRules, .editInfo, .deleteList]
        }
        // A URL-imported custom list can be inspected or removed, and its
        // name, description, and category edited, but not its rules.
        return [.info, .settings, .viewRules, .editInfo, .deleteList]
    }

    static func userScriptActions(isBuiltIn: Bool, isLocal: Bool) -> [UserScriptContextMenuAction] {
        userScriptActions(isBuiltIn: isBuiltIn, isLocal: isLocal, isDownloaded: true)
    }

    /// Remote scripts that have no content yet get an explicit Download action
    /// (#665) so fetching does not require enabling them first.
    static func userScriptActions(
        isBuiltIn: Bool,
        isLocal: Bool,
        isDownloaded: Bool
    ) -> [UserScriptContextMenuAction] {
        let download: [UserScriptContextMenuAction] = (!isLocal && !isDownloaded) ? [.download] : []
        guard !isBuiltIn else { return [.info, .settings, .viewContent] + download }
        if isLocal {
            return [.info, .settings, .editContent, .editInfo, .deleteScript]
        }
        // A URL-imported custom script is view-only with respect to its source.
        return [.info, .settings, .viewContent, .editInfo] + download + [.deleteScript]
    }
}
