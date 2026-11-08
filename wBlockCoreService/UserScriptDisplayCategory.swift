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
}
