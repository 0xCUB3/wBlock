//
//  AppConstants.swift
//  wBlock
//
//  Created by Alexander Skula on 11/25/24.
//

import Foundation

struct AppConstants {
    // Bundle Identifiers
    struct BundleIdentifier {
        static let mainApp = "app.0xcube.wBlock"
        static let scriptsExtension = "app.0xcube.wBlock.wBlockScripts"
        static let filtersExtension = "app.0xcube.wBlock.wBlockFilters"
    }
    
    // Logger Subsystems
    struct LoggerSubsystem {
        static let mainApp = BundleIdentifier.mainApp
        static let scriptsExtension = BundleIdentifier.scriptsExtension
        static let filtersExtension = BundleIdentifier.filtersExtension
    }
    
    // App Group Identifier
    static let appGroupIdentifier = "group.app.0xcube.wBlock"
}
