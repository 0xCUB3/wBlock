//
//  TubeCleanerDeArrowPreference.swift
//  wBlockCoreService
//

import Foundation

/// App-managed DeArrow settings for the built-in Tube Cleaner script. The
/// script used to keep these in page localStorage behind a "DA" pill on the
/// player; they now live in the app group and are prepended to the script as
/// a constant, the same way Dark Reader receives its appearance preference.
public enum TubeCleanerDeArrowPreference {
    public struct Settings: Codable, Equatable, Sendable {
        public var enabled = false
        public var replaceTitles = true
        public var replaceThumbnails = true
        public var randomThumbnails = false
        public var showOriginalOnHover = true

        public init() {}
    }

    public static let storageKey = "tubeCleanerDeArrow"
    public static let storageSuiteName = "group.skula.wBlock"
    public static let scriptURL =
        "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/tube-cleaner/dist/tube-cleaner.user.js"
    public static let settingsConstantName = "__wblockTubeCleanerDeArrow"

    public static func settings(groupIdentifier: String = storageSuiteName) -> Settings {
        guard let data = UserDefaults(suiteName: groupIdentifier)?.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    public static func setSettings(_ settings: Settings, groupIdentifier: String = storageSuiteName) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults(suiteName: groupIdentifier)?.set(data, forKey: storageKey)
    }

    public static func matches(scriptURL: URL?) -> Bool {
        scriptURL?.absoluteString == self.scriptURL
    }

    public static func configuredExecutableContent(
        _ executableContent: String,
        settings: Settings
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = (try? encoder.encode(settings)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "const \(settingsConstantName) = \(json);\n\(executableContent)"
    }
}
