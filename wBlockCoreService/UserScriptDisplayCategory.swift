import Foundation

public enum BuiltInUserScriptDisplayRole: String, Hashable, Sendable {
    case blocking
    case functionality
}

public enum UserScriptDisplayCategory: String, CaseIterable, Hashable, Sendable, Identifiable {
    case blocking = "Blocking"
    case functionality = "Functionality"
    case experimental = "Experimental"
    case appearance = "Appearance"
    case other = "Other"

    public var id: String { rawValue }

    public var descriptionKey: String {
        switch self {
        case .blocking:
            "Blocking userscripts and scripts that prevent ads, anti-adblock measures, or unwanted page behavior."
        case .functionality:
            "Userscripts and scripts that add or restore useful website functionality."
        case .experimental:
            "Beta userscripts and scripts that are still being evaluated or may change."
        case .appearance:
            "Userstyles and scripts that change the appearance of websites."
        case .other:
            "Custom, remote, and local scripts that do not have a more specific display category."
        }
    }
}

public struct UserScriptDisplayCategorySupport {
    public static func category(
        isUserStyle: Bool,
        builtInRole: BuiltInUserScriptDisplayRole?,
        persistedCategory: FilterListCategory,
        isBeta: Bool = false
    ) -> UserScriptDisplayCategory {
        switch persistedCategory {
        case .scriptBlocking: return .blocking
        case .scriptFunctionality: return .functionality
        case .scriptExperimental: return .experimental
        case .scriptAppearance: return .appearance
        case .scriptOther: return .other
        default: break
        }
        if isUserStyle { return .appearance }
        if isBeta { return .experimental }
        switch builtInRole {
        case .blocking:
            return .blocking
        case .functionality:
            return .functionality
        case nil:
            // FilterListCategory remains the persisted organization field. The
            // existing Scripts/Custom values do not imply a display role.
            _ = persistedCategory
            return .other
        }
    }

    public static func orderedGroups<T>(
        _ items: [T],
        category: (T) -> UserScriptDisplayCategory
    ) -> [(category: UserScriptDisplayCategory, items: [T])] {
        UserScriptDisplayCategory.allCases.compactMap { displayCategory in
            let matching = items.filter { category($0) == displayCategory }
            return matching.isEmpty ? nil : (displayCategory, matching)
        }
    }
}
