//
//  CosmeticFilteringPreference.swift
//  wBlockCoreService
//
//  Shared "cosmetic filtering" switch (#610) and its site scope (#899). Off
//  drops element-hiding and CSS rules before conversion so Safari never
//  evaluates them; a scope ties them to, or keeps them off, specific sites.
//  Scriptlet rules are not cosmetic and are kept.
//

internal import ContentBlockerConverter
import Foundation

public enum CosmeticFilteringPreference {
    public static let storageKey = "cosmeticFilteringEnabled"
    public static let sitesStorageKey = "cosmeticFilteringSites"

    /// Where cosmetic rules apply, in the same shape as a list's site scope.
    public struct Sites: Codable, Equatable, Sendable {
        public var selectedSites: [String]?
        public var excludedSites: [String]

        public static let all = Sites()

        public init(selectedSites: [String]? = nil, excludedSites: [String] = []) {
            self.selectedSites = selectedSites.map { FilterListSiteExclusion.normalizedDomains(from: $0) }
            self.excludedSites = FilterListSiteExclusion.normalizedDomains(from: excludedSites)
        }

        /// Folded into cache identity; nil leaves existing caches valid.
        var cacheMarker: String? {
            self == .all ? nil : FilterListSiteExclusion.scopeMarker(excluding: excludedSites, including: selectedSites)
        }

        public func restricting(_ rules: String) -> String {
            FilterListSiteExclusion.restrictingCosmeticRules(rules, excluding: excludedSites, including: selectedSites)
        }
    }

    public static func isEnabled(groupIdentifier: String = GroupIdentifier.shared.value) -> Bool {
        guard let defaults = UserDefaults(suiteName: groupIdentifier),
              defaults.object(forKey: storageKey) != nil
        else { return true }
        return defaults.bool(forKey: storageKey)
    }

    public static func setEnabled(_ enabled: Bool, groupIdentifier: String = GroupIdentifier.shared.value) {
        UserDefaults(suiteName: groupIdentifier)?.set(enabled, forKey: storageKey)
    }

    public static func sites(groupIdentifier: String = GroupIdentifier.shared.value) -> Sites {
        guard let data = UserDefaults(suiteName: groupIdentifier)?.data(forKey: sitesStorageKey),
              let sites = try? JSONDecoder().decode(Sites.self, from: data)
        else { return .all }
        return sites
    }

    public static func setSites(_ sites: Sites, groupIdentifier: String = GroupIdentifier.shared.value) {
        UserDefaults(suiteName: groupIdentifier)?.set(try? JSONEncoder().encode(sites), forKey: sitesStorageKey)
    }

    /// The scope compilation honors. Turning the switch off selects no sites.
    public static func effectiveSites(groupIdentifier: String = GroupIdentifier.shared.value) -> Sites {
        isEnabled(groupIdentifier: groupIdentifier) ? sites(groupIdentifier: groupIdentifier) : Sites(selectedSites: [])
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
}
