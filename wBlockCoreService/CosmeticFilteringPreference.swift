//
//  CosmeticFilteringPreference.swift
//  wBlockCoreService
//
//  Shared "cosmetic filtering" switch (#610) and its site scope (#899). Off
//  drops element-hiding and CSS rules before conversion so Safari never
//  evaluates them; a scope ties them to, or keeps them off, specific sites.
//  Scriptlet rules are not cosmetic and are kept.
//

import Foundation

public enum CosmeticFilteringPreference {
    public static let storageKey = "cosmeticFilteringEnabled"
    public static let sitesStorageKey = "cosmeticFilteringSites"

    /// Where cosmetic rules apply, in the same shape as a list's site scope.
    public struct Sites: Codable, Equatable, Sendable {
        public var selectedSites: [String]?
        public var excludedSites: [String]
        private var selectedSitesOnly: Bool?

        public var onlySelectedSites: Bool {
            get { selectedSitesOnly ?? (selectedSites != nil) }
            set { selectedSitesOnly = newValue }
        }
        /// Nil keeps generic rules (those naming no site), which every frame
        /// on every site has to match against.
        private var genericRules: Bool?

        public var includesGeneric: Bool { genericRules != false }

        public static let all = Sites()

        public init(selectedSites: [String]? = nil, excludedSites: [String] = [], includesGeneric: Bool = true) {
            self.selectedSites = selectedSites.map { FilterListSiteExclusion.normalizedDomains(from: $0) }
            self.excludedSites = FilterListSiteExclusion.normalizedDomains(from: excludedSites)
            self.genericRules = includesGeneric ? nil : false
        }

        /// Folded into cache identity; nil leaves existing caches valid.
        var cacheMarker: String? {
            guard self != .all else { return nil }
            let marker = FilterListSiteExclusion.scopeMarker(excluding: excludedSites, including: selectedSites)
            return includesGeneric ? marker : marker + "|generic=off"
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

    /// The master switch disables cosmetic rules; the site mode independently
    /// picks which saved list applies without discarding the inactive list.
    public static func effectiveSites(groupIdentifier: String = GroupIdentifier.shared.value) -> Sites {
        let saved = sites(groupIdentifier: groupIdentifier)
        guard isEnabled(groupIdentifier: groupIdentifier) else { return Sites(selectedSites: []) }
        return saved.onlySelectedSites
            ? Sites(selectedSites: saved.selectedSites ?? [], includesGeneric: saved.includesGeneric)
            : Sites(excludedSites: saved.excludedSites, includesGeneric: saved.includesGeneric)
    }

}
