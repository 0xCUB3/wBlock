//
//  DarkReaderAppearancePreference.swift
//  wBlockCoreService
//

import Foundation

public enum DarkReaderAppearancePreference {
    public static let storageKey = "darkReaderFollowsSystemAppearance"
    public static let storageSuiteName = "group.skula.wBlock"
    public static let scriptURL =
        "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/dark-reader/dist/dark-reader.user.js"

    public static func followsSystemAppearance(
        groupIdentifier: String = storageSuiteName
    ) -> Bool {
        guard let defaults = UserDefaults(suiteName: groupIdentifier),
              defaults.object(forKey: storageKey) != nil
        else { return true }
        return defaults.bool(forKey: storageKey)
    }

    public static func setFollowsSystemAppearance(
        _ followsSystemAppearance: Bool,
        groupIdentifier: String = storageSuiteName
    ) {
        UserDefaults(suiteName: groupIdentifier)?.set(
            followsSystemAppearance,
            forKey: storageKey
        )
    }

    public static func matches(scriptURL: URL?) -> Bool {
        scriptURL?.absoluteString == self.scriptURL
    }

    public static func configuredExecutableContent(
        _ executableContent: String,
        followsSystemAppearance: Bool
    ) -> String {
        let value = followsSystemAppearance ? "true" : "false"
        return "const __wblockDarkReaderFollowsSystemAppearance = \(value);\n\(executableContent)"
    }
}
