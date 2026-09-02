//
//  CosmeticFilteringPreference.swift
//  wBlockCoreService
//
//  Shared "cosmetic filtering" switch (#610). When off, element-hiding and CSS
//  rules are dropped before conversion so Safari never evaluates them. Scriptlet
//  rules are not cosmetic and are kept.
//

internal import ContentBlockerConverter
import Foundation

public enum CosmeticFilteringPreference {
    public static let storageKey = "cosmeticFilteringEnabled"

    public static func isEnabled(groupIdentifier: String = GroupIdentifier.shared.value) -> Bool {
        guard let defaults = UserDefaults(suiteName: groupIdentifier),
              defaults.object(forKey: storageKey) != nil
        else { return true }
        return defaults.bool(forKey: storageKey)
    }

    public static func setEnabled(_ enabled: Bool, groupIdentifier: String = GroupIdentifier.shared.value) {
        UserDefaults(suiteName: groupIdentifier)?.set(enabled, forKey: storageKey)
    }

    /// True for element-hiding and CSS injection rules, using the converter's own
    /// marker detection so classification matches what it would compile.
    public static func isCosmeticRule(_ line: String) -> Bool {
        // Comments can contain marker text; the converter drops them anyway.
        guard let first = line.utf8.first, first != UInt8(ascii: "!") else { return false }
        switch CosmeticRuleMarker.findCosmeticRuleMarker(ruleText: line).marker {
        case .elementHiding, .elementHidingException, .elementHidingExtCSS, .elementHidingExtCSSException,
             .css, .cssException, .cssExtCSS, .cssExtCSSException:
            return true
        case .javascript, .javascriptException, .html, .htmlException, nil:
            return false
        }
    }

    public static func strippingCosmeticRules(from rules: String) -> String {
        rules.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .filter { !isCosmeticRule(String($0)) }
            .joined(separator: "\n")
    }
}
