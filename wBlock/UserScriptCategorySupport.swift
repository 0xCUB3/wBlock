import Foundation
import wBlockCoreService

enum UserScriptCategorySupport {
    static func defaultScriptNames(
        for category: UserScriptDisplayCategory,
        scripts: [(name: String, displayCategory: UserScriptDisplayCategory, isEnabledByDefault: Bool)]
    ) -> [String] {
        scripts
            .filter { $0.displayCategory == category && $0.isEnabledByDefault }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func resetEnabled(
        isBuiltIn: Bool,
        displayCategory: UserScriptDisplayCategory,
        category: UserScriptDisplayCategory,
        isEnabledByDefault: Bool
    ) -> Bool? {
        guard displayCategory == category else { return nil }
        guard isBuiltIn else { return nil }
        return isEnabledByDefault
    }
}
