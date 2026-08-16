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

    /// Name of the constant prepended to the script so the adapter can read the
    /// preference. Content that does not reference it predates the appearance
    /// setting and cannot honor it.
    public static let appearanceFlagName = "__wblockDarkReaderFollowsSystemAppearance"

    /// Marker present in adapter builds that withdraw the theme on natively dark
    /// pages (the detector ported from Dark Reader's src/inject/detector.ts).
    /// Content without it re-maps already-dark sites, washing out their colors.
    public static let darkThemeDetectionMarkerName = "detectBuiltInDarkTheme"

    public static func configuredExecutableContent(
        _ executableContent: String,
        followsSystemAppearance: Bool
    ) -> String {
        let value = followsSystemAppearance ? "true" : "false"
        return "const \(appearanceFlagName) = \(value);\n\(executableContent)"
    }
}

