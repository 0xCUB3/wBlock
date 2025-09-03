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

    init(primaryCategory: FilterListCategory, platform: Platform, bundleIdentifier: String, rulesFilename: String) {
        self.primaryCategory = primaryCategory
        self.platform = platform
        self.bundleIdentifier = bundleIdentifier
        self.rulesFilename = rulesFilename
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
            // Universal targets for both macOS and iOS
            ContentBlockerTargetInfo(primaryCategory: .ads, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Ads-Privacy", rulesFilename: "rules_ads_privacy.json"),
            ContentBlockerTargetInfo(primaryCategory: .security, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Security-Multipurpose", rulesFilename: "rules_security_multipurpose.json"),
            ContentBlockerTargetInfo(primaryCategory: .annoyances, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Annoyances", rulesFilename: "rules_annoyances.json"),
            ContentBlockerTargetInfo(primaryCategory: .foreign, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Foreign-Experimental", rulesFilename: "rules_foreign_experimental.json"),
            ContentBlockerTargetInfo(primaryCategory: .custom, platform: .macOS, bundleIdentifier: "skula.wBlock.wBlock-Custom", rulesFilename: "rules_custom.json"),
            
            // iOS uses the same extensions and rules files
            ContentBlockerTargetInfo(primaryCategory: .ads, platform: .iOS, bundleIdentifier: "skula.wBlock.wBlock-Ads-Privacy", rulesFilename: "rules_ads_privacy.json"),
            ContentBlockerTargetInfo(primaryCategory: .security, platform: .iOS, bundleIdentifier: "skula.wBlock.wBlock-Security-Multipurpose", rulesFilename: "rules_security_multipurpose.json"),
            ContentBlockerTargetInfo(primaryCategory: .annoyances, platform: .iOS, bundleIdentifier: "skula.wBlock.wBlock-Annoyances", rulesFilename: "rules_annoyances.json"),
            ContentBlockerTargetInfo(primaryCategory: .foreign, platform: .iOS, bundleIdentifier: "skula.wBlock.wBlock-Foreign-Experimental", rulesFilename: "rules_foreign_experimental.json"),
            ContentBlockerTargetInfo(primaryCategory: .custom, platform: .iOS, bundleIdentifier: "skula.wBlock.wBlock-Custom", rulesFilename: "rules_custom.json")
        ]
    }

    public func targetInfo(forCategory category: FilterListCategory, platform: Platform) -> ContentBlockerTargetInfo? {
        return targets.first { $0.platform == platform && $0.primaryCategory == category }
    }
    
    public func allTargets(forPlatform platform: Platform) -> [ContentBlockerTargetInfo] {
        return targets.filter { $0.platform == platform }
    }
}
