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
    public static let compiledSitesStorageKey = "cosmeticFilteringCompiledSites"

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

        /// Whether cosmetic rules apply on `host` under this site scope.
        public func allows(host: String) -> Bool {
            onlySelectedSites
                ? CosmeticFilteringPreference.matchesHost(host, entries: selectedSites ?? [])
                : !CosmeticFilteringPreference.matchesHost(host, entries: excludedSites)
        }
    }

    /// Matches a hostname against exact domains, parent domains, and `name.*` wildcards.
    public static func matchesHost(_ host: String, entries: [String]) -> Bool {
        guard let normalizedHost = DisabledSitesNormalizer.normalizedDomain(host) else { return false }
        for rawEntry in entries {
            guard let entry = FilterListSiteExclusion.normalizedDomain(rawEntry) else { continue }
            if entry.hasSuffix(".*") {
                let prefix = String(entry.dropLast(2))
                if normalizedHost.hasPrefix(prefix + ".") && normalizedHost.count > prefix.count + 1 {
                    return true
                }
                if let range = normalizedHost.range(of: "." + prefix + "."),
                   range.upperBound < normalizedHost.endIndex {
                    return true
                }
            } else if HostMatcher.isHostDisabled(host: normalizedHost, disabledSites: [entry]) {
                return true
            }
        }
        return false
    }

    public static func isEnabled(groupIdentifier: String = GroupIdentifier.shared.value) -> Bool {
        guard let defaults = UserDefaults(suiteName: groupIdentifier),
              defaults.object(forKey: storageKey) != nil
        else { return true }
        return defaults.bool(forKey: storageKey)
    }

    public static func isEnabled(onHost host: String, isEnabled: Bool, sites: Sites) -> Bool {
        guard isEnabled else { return false }
        return sites.allows(host: host)
    }

    public static func isEnabled(onHost host: String, groupIdentifier: String = GroupIdentifier.shared.value) -> Bool {
        isEnabled(onHost: host, isEnabled: isEnabled(groupIdentifier: groupIdentifier), sites: sites(groupIdentifier: groupIdentifier))
    }

    /// Returns an updated site scope with cosmetic filtering turned on or off for `host`,
    /// preserving the active mode, generic-rules setting, and inactive list.
    public static func updating(sites: Sites, enabled: Bool, onHost host: String) -> Sites {
        guard let normalizedHost = DisabledSitesNormalizer.normalizedDomain(host) else { return sites }
        var updated = sites
        if sites.onlySelectedSites {
            var selected = sites.selectedSites ?? []
            if enabled {
                if !matchesHost(normalizedHost, entries: selected) {
                    selected.append(normalizedHost)
                }
            } else {
                selected.removeAll { matchesHost(normalizedHost, entries: [$0]) }
            }
            updated.selectedSites = FilterListSiteExclusion.normalizedDomains(from: selected)
            updated.onlySelectedSites = true
        } else {
            var excluded = sites.excludedSites
            if enabled {
                excluded.removeAll { matchesHost(normalizedHost, entries: [$0]) }
            } else {
                if !matchesHost(normalizedHost, entries: excluded) {
                    excluded.append(normalizedHost)
                }
            }
            updated.excludedSites = FilterListSiteExclusion.normalizedDomains(from: excluded)
        }
        return updated
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

    public static func compiledSites(groupIdentifier: String = GroupIdentifier.shared.value) -> Sites? {
        guard let data = UserDefaults(suiteName: groupIdentifier)?.data(forKey: compiledSitesStorageKey),
              let sites = try? JSONDecoder().decode(Sites.self, from: data)
        else { return nil }
        return sites
    }

    public static func recordCompiledSites(_ sites: Sites, groupIdentifier: String = GroupIdentifier.shared.value) {
        UserDefaults(suiteName: groupIdentifier)?.set(try? JSONEncoder().encode(sites), forKey: compiledSitesStorageKey)
    }

    /// Sites that need a fast-path `css-display-none` ignore rule in Safari content blockers
    /// because cosmetic filtering is currently off on them while the last compiled output still
    /// includes their hides.
    public static func fastPathDisabledSites(
        isEnabled: Bool,
        sites: Sites,
        compiledSites: Sites? = nil
    ) -> [String] {
        guard isEnabled else { return [] }
        if sites.onlySelectedSites {
            guard let compiled = compiledSites, compiled.onlySelectedSites else { return [] }
            return FilterListSiteExclusion.normalizedDomains(
                from: (compiled.selectedSites ?? []).filter { !matchesHost($0, entries: sites.selectedSites ?? []) }
            )
        }
        guard let compiled = compiledSites, !compiled.onlySelectedSites else {
            return FilterListSiteExclusion.normalizedDomains(from: sites.excludedSites)
        }
        return FilterListSiteExclusion.normalizedDomains(
            from: sites.excludedSites.filter { !matchesHost($0, entries: compiled.excludedSites) }
        )
    }

    public static func currentFastPathDisabledSites(groupIdentifier: String = GroupIdentifier.shared.value) -> [String] {
        fastPathDisabledSites(
            isEnabled: isEnabled(groupIdentifier: groupIdentifier),
            sites: sites(groupIdentifier: groupIdentifier),
            compiledSites: compiledSites(groupIdentifier: groupIdentifier)
        )
    }

    /// Whether turning cosmetic filtering on for `host` needs a full apply because the last
    /// compiled output stripped that host's cosmetic rules.
    public static func requiresFullApply(enablingHost host: String, compiledSites: Sites?) -> Bool {
        guard let compiledSites else { return true }
        return !compiledSites.allows(host: host)
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
