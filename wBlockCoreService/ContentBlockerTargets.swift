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
    public let primaryCategory: FilterListCategory
    public let platform: Platform
    public let bundleIdentifier: String
    public let rulesFilename: String
    public let secondaryCategory: FilterListCategory?

    init(primaryCategory: FilterListCategory, platform: Platform, bundleIdentifier: String, rulesFilename: String, secondaryCategory: FilterListCategory? = nil) {
        self.primaryCategory = primaryCategory
        self.platform = platform
        self.bundleIdentifier = bundleIdentifier
        self.rulesFilename = rulesFilename
        self.secondaryCategory = secondaryCategory
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
            // macOS Targets
            ContentBlockerTargetInfo(primaryCategory: .ads, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Ads-Privacy", rulesFilename: "rules_ads_privacy_macos.json", secondaryCategory: .privacy),
            ContentBlockerTargetInfo(primaryCategory: .security, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Security-Multipurpose", rulesFilename: "rules_security_multipurpose_macos.json", secondaryCategory: .multipurpose),
            ContentBlockerTargetInfo(primaryCategory: .annoyances, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Annoyances", rulesFilename: "rules_annoyances_macos.json"),
            ContentBlockerTargetInfo(primaryCategory: .foreign, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Foreign-Experimental", rulesFilename: "rules_foreign_experimental_macos.json", secondaryCategory: .experimental),
            ContentBlockerTargetInfo(primaryCategory: .custom, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Custom", rulesFilename: "rules_custom_macos.json")
        ]
    }

    public func targetInfo(forCategory category: FilterListCategory, platform: Platform) -> ContentBlockerTargetInfo? {
        return targets.first { $0.platform == platform && ($0.primaryCategory == category || $0.secondaryCategory == category) }
    }
    
    public func allTargets(forPlatform platform: Platform) -> [ContentBlockerTargetInfo] {
        return targets.filter { $0.platform == platform }
    }
}
