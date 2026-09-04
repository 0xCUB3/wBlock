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
    case download
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
        guard !isBuiltIn else { return [.info, .viewContent] + download }
        if isLocal {
            return [.info, .editContent, .deleteScript]
        }
        // A URL-imported custom script is view-only with respect to its source.
        return [.info, .viewContent] + download + [.deleteScript]
    }
}
