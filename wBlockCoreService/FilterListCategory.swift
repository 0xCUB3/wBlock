//
//  FilterListCategory.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import Combine
import Foundation

public enum FilterListCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "All"
    case ads = "Ads"
    case privacy = "Privacy"
    case security = "Security"
    case multipurpose = "Multipurpose"
    case annoyances = "Annoyances"
    case experimental = "Experimental"
    case allowlists = "Allowlists"
    case custom = "Custom"
    case foreign = "Foreign"
    case scripts = "Scripts"
    case scriptBlocking = "Blocking"
    case scriptFunctionality = "Functionality"
    case scriptAppearance = "Appearance"
    case scriptOther = "Other"

    public var isUserScriptOnly: Bool {
        [.scriptBlocking, .scriptFunctionality, .scriptAppearance, .scriptOther].contains(self)
    }

    public var id: String { self.rawValue }
}
