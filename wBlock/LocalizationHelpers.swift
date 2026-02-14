//
//  LocalizationHelpers.swift
//  wBlock
//
//  Created by Codex on 2/13/26.
//

import Foundation
import wBlockCoreService

extension FilterListCategory {
    var localizedName: String {
        NSLocalizedString(rawValue, comment: "Filter list category")
    }
}

extension LogLevel {
    var localizedName: String {
        switch self {
        case .trace:
            return NSLocalizedString("Trace", comment: "Log level")
        case .debug:
            return NSLocalizedString("Debug", comment: "Log level")
        case .info:
            return NSLocalizedString("Info", comment: "Log level")
        case .warning:
            return NSLocalizedString("Warning", comment: "Log level")
        case .error:
            return NSLocalizedString("Error", comment: "Log level")
        }
    }
}

extension LogCategory {
    var localizedName: String {
        switch self {
        case .system:
            return NSLocalizedString("System", comment: "Log category")
        case .filterUpdate:
            return NSLocalizedString("Filter Update", comment: "Log category")
        case .filterApply:
            return NSLocalizedString("Filter Apply", comment: "Log category")
        case .userScript:
            return NSLocalizedString("Userscript", comment: "Log category")
        case .network:
            return NSLocalizedString("Network", comment: "Log category")
        case .whitelist:
            return NSLocalizedString("Whitelist", comment: "Log category")
        case .autoUpdate:
            return NSLocalizedString("Auto Update", comment: "Log category")
        case .startup:
            return NSLocalizedString("Startup", comment: "Log category")
        }
    }
}
