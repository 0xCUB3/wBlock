//
//  PlayerCleanerPreference.swift
//  wBlockCoreService
//

import Foundation

/// Per-feature switches for Player Cleaner. Everything defaults to on so the
/// script behaves as before until someone turns something off. The switches
/// are prepended to the script as `__wblockPlayerCleanerFeatures`.
public enum PlayerCleanerPreference {
    public struct Features: Codable, Equatable, Sendable {
        public var autoPictureInPicture = true
        public var backgroundPlayback = true

        public init() {}

        public var allEnabled: Bool { self == Features() }
        public var disabledCount: Int {
            [autoPictureInPicture, backgroundPlayback].filter { !$0 }.count
        }
    }

    public static let featuresStorageKey = "playerCleanerFeatures"
    public static let storageSuiteName = "group.skula.wBlock"
    public static let scriptURL =
        "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/player-cleaner/dist/player-cleaner.user.js"
    public static let featuresConstantName = "__wblockPlayerCleanerFeatures"

    public static func features(groupIdentifier: String = storageSuiteName) -> Features {
        guard let data = UserDefaults(suiteName: groupIdentifier)?.data(forKey: featuresStorageKey),
              let features = try? JSONDecoder().decode(Features.self, from: data)
        else { return Features() }
        return features
    }

    public static func setFeatures(_ features: Features, groupIdentifier: String = storageSuiteName) {
        guard let data = try? JSONEncoder().encode(features) else { return }
        UserDefaults(suiteName: groupIdentifier)?.set(data, forKey: featuresStorageKey)
    }

    public static func matches(scriptURL: URL?) -> Bool {
        scriptURL?.absoluteString == self.scriptURL
    }

    public static func configuredExecutableContent(
        _ executableContent: String,
        features: Features = Features()
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = (try? encoder.encode(features)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "const \(featuresConstantName) = \(json);\n\(executableContent)"
    }
}
