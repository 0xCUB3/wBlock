//
//  FilterListSiteExclusion.swift
//  wBlockCoreService
//
//  Per-list site scope (issues #653, #767, #925, #1032). The engine applies it
//  to parsed rules (Packages/wblock-engine/crates/wbe/src/apply.rs); this file
//  normalizes the sites it is given and keys caches on them.
//

import Foundation

public enum FilterListSiteExclusion {
    /// A site, or `name.*` for every domain ending (#1032), which filter rule
    /// syntax matches natively.
    public static func normalizedDomain(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(".*") else { return DisabledSitesNormalizer.normalizedDomain(trimmed) }
        return DisabledSitesNormalizer.normalizedDomain(String(trimmed.dropLast(2))).map { $0 + ".*" }
    }

    public static func normalizedDomains(from raw: [String]) -> [String] {
        Array(Set(raw.compactMap(normalizedDomain))).sorted()
    }

    /// The page-URL pattern for a `name.*` domain, which `if-domain` cannot
    /// express. Used with `if-top-url`, which every supported Safari has
    /// (`if-frame-url` needs a newer one).
    static func wildcardTopURLPattern(_ site: String) -> String? {
        guard site.hasSuffix(".*") else { return nil }
        let name = NSRegularExpression.escapedPattern(for: String(site.dropLast(2)))
        return #"^[^:]+://+([^:/]+\.)?"# + name + #"\.[^/:]+([/:?#].*)?$"#
    }

    /// Cache identity for a site scope, since it changes compiled output
    /// without touching any list file.
    static func scopeMarker(excluding excluded: [String], including selected: [String]?) -> String {
        let marker = excluded.sorted().joined(separator: ",")
        guard let selected else { return marker }
        return marker + "|selected=" + selected.sorted().joined(separator: ",")
    }
}
