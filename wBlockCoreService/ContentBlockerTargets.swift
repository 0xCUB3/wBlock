//
//  ContentBlockerTargets.swift
//  wBlock
//
//  Created by Alexander Skula on 5/25/25.
//

import Foundation

public enum Platform {
    case macOS
    case iOS
}

public struct ContentBlockerTargetInfo: Hashable {
    /// Stable slot index shown to users (e.g. "wBlock 1").
    public let slot: Int
    public let platform: Platform
    public let bundleIdentifier: String
    public let rulesFilename: String
    public let displayName: String

    init(slot: Int, platform: Platform, bundleIdentifier: String, rulesFilename: String, displayName: String) {
        self.slot = slot
        self.platform = platform
        self.bundleIdentifier = bundleIdentifier
        self.rulesFilename = rulesFilename
        self.displayName = displayName
    }

    // Implement Hashable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }

    public static func == (lhs: ContentBlockerTargetInfo, rhs: ContentBlockerTargetInfo) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

public class ContentBlockerTargetManager {
    public static let shared = ContentBlockerTargetManager()

    public let targets: [ContentBlockerTargetInfo]

    private init() {
        targets = [
            // macOS Targets (5 content blockers)
            ContentBlockerTargetInfo(slot: 1, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Ads", rulesFilename: "rules_ads_macos.json", displayName: "wBlock 1"),
            ContentBlockerTargetInfo(slot: 2, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Privacy", rulesFilename: "rules_privacy_macos.json", displayName: "wBlock 2"),
            ContentBlockerTargetInfo(slot: 3, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Security", rulesFilename: "rules_security_annoyances_macos.json", displayName: "wBlock 3"),
            ContentBlockerTargetInfo(slot: 4, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Foreign", rulesFilename: "rules_foreign_experimental_macos.json", displayName: "wBlock 4"),
            ContentBlockerTargetInfo(slot: 5, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Custom", rulesFilename: "rules_custom_macos.json", displayName: "wBlock 5"),

            // iOS Targets (same 5 slots as macOS)
            ContentBlockerTargetInfo(slot: 1, platform: .iOS, bundleIdentifier: "skula.wBlock.wBlock-Ads-iOS", rulesFilename: "rules_ads_ios.json", displayName: "wBlock 1"),
            ContentBlockerTargetInfo(slot: 2, platform: .iOS, bundleIdentifier: "skula.wBlock.wBlock-Privacy-iOS", rulesFilename: "rules_privacy_ios.json", displayName: "wBlock 2"),
            ContentBlockerTargetInfo(slot: 3, platform: .iOS, bundleIdentifier: "skula.wBlock.wBlock-Security-iOS", rulesFilename: "rules_security_annoyances_ios.json", displayName: "wBlock 3"),
            ContentBlockerTargetInfo(slot: 4, platform: .iOS, bundleIdentifier: "skula.wBlock.wBlock-Foreign-iOS", rulesFilename: "rules_foreign_experimental_ios.json", displayName: "wBlock 4"),
            ContentBlockerTargetInfo(slot: 5, platform: .iOS, bundleIdentifier: "skula.wBlock.wBlock-Custom-iOS", rulesFilename: "rules_custom_ios.json", displayName: "wBlock 5")
        ]
    }
    
    public func allTargets(forPlatform platform: Platform) -> [ContentBlockerTargetInfo] {
        targets.filter { $0.platform == platform }.sorted { $0.slot < $1.slot }
    }

    public func targetInfo(forBundleIdentifier bundleIdentifier: String, platform: Platform) -> ContentBlockerTargetInfo? {
        targets.first { $0.platform == platform && $0.bundleIdentifier == bundleIdentifier }
    }
}
