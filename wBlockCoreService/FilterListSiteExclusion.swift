//
//  FilterListSiteExclusion.swift
//  wBlockCoreService
//
//  Per-list site exclusions (issue #653). Rules from one list get domain
//  negations (or lose matching positive domains) so the list does not apply on
//  the excluded hosts while other lists in the same blocker still do.
//
//  Safari's converter rejects network rules that mix permitted and restricted
//  domains, so a rule that is already scoped to specific sites is narrowed by
//  removing the excluded ones instead of appending negations. When an excluded
//  site is a subdomain of a scoped site (issue #767), the scope cannot be
//  narrowed: cosmetic rules gain a negation (Safari 16.4+ converts those into
//  per-domain entries) and network rules get a companion exception scoped to
//  the excluded subdomain.
//

import Foundation

public enum FilterListSiteExclusion {
    public static func normalizedDomains(from raw: [String]) -> [String] {
        DisabledSitesNormalizer.normalizedDomains(from: raw)
    }

    public static func restrictingAdvancedRules(_ text: String, excluding domains: [String]) -> String {
        let sites = normalizedDomains(from: domains)
        guard !sites.isEmpty, !text.isEmpty else { return text }

        return text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { restrictAdvancedLine(String($0), excluding: sites) }
            .joined(separator: "\n")
    }

    private static let cosmeticSeparators = ["#@$?#", "#$?#", "#@%#", "#%#", "#@?#", "#@$#", "#?#", "#$#", "#@#", "##"]

    private static func restrictAdvancedLine(_ line: String, excluding sites: [String]) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("!") {
            return line
        }

        if let cosmetic = splitCosmetic(trimmed) {
            return restrictCosmetic(cosmetic, excluding: sites) ?? ""
        }
        return restrictNetworkLine(trimmed, excluding: sites) ?? ""
    }

    private static func splitCosmetic(_ line: String) -> (domains: String, separator: String, body: String)? {
        for separator in cosmeticSeparators {
            guard let range = line.range(of: separator) else { continue }
            return (
                domains: String(line[..<range.lowerBound]),
                separator: separator,
                body: String(line[range.upperBound...])
            )
        }
        return nil
    }

    private struct RestrictedDomains {
        var positives: [String]
        var negatives: [String]
        /// Excluded sites that are proper subdomains of a kept positive domain.
        /// The positive scope still matches them, so they need explicit handling.
        var uncoveredSubdomains: [String]

        var joined: [String] { positives + negatives }
    }

    private static func covers(_ host: String, _ site: String) -> Bool {
        host == site || site.hasSuffix(".\(host)")
    }

    /// Narrows a domain list so it never matches an excluded site.
    /// Returns nil when the rule was scoped to sites that are all excluded.
    private static func restrictDomainList(_ domains: [String], excluding sites: [String]) -> RestrictedDomains? {
        let positives = domains.filter { !$0.hasPrefix("~") }
        var negatives = domains.filter { $0.hasPrefix("~") }
        let negatedHosts = negatives.map { String($0.dropFirst()) }

        if positives.isEmpty {
            for site in sites where !negatedHosts.contains(where: { covers($0, site) }) {
                negatives.append("~\(site)")
            }
            return RestrictedDomains(positives: [], negatives: negatives, uncoveredSubdomains: [])
        }

        let kept = positives.filter { host in
            !sites.contains { site in covers(site, host) }
        }
        if kept.isEmpty { return nil }

        let uncovered = sites.filter { site in
            kept.contains { host in host != site && covers(host, site) }
                && !negatedHosts.contains { covers($0, site) }
        }
        return RestrictedDomains(positives: kept, negatives: negatives, uncoveredSubdomains: uncovered)
    }

    private static func restrictCosmetic(
        _ cosmetic: (domains: String, separator: String, body: String),
        excluding sites: [String]
    ) -> String? {
        let rawDomains = cosmetic.domains
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let restricted = restrictDomainList(rawDomains, excluding: sites) else { return nil }
        let negations = restricted.uncoveredSubdomains.map { "~\($0)" }
        return (restricted.joined + negations).joined(separator: ",") + cosmetic.separator + cosmetic.body
    }

    private static func restrictNetworkLine(_ line: String, excluding sites: [String]) -> String? {
        let negations = sites.map { "~\($0)" }.joined(separator: "|")
        guard let dollar = line.lastIndex(of: "$") else {
            return "\(line)$domain=\(negations)"
        }

        let body = String(line[..<dollar])
        let options = String(line[line.index(after: dollar)...])
        var parts = options.split(separator: ",", omittingEmptySubsequences: false).map(String.init)

        guard let domainIndex = parts.firstIndex(where: { $0.hasPrefix("domain=") }) else {
            if options.isEmpty {
                return "\(body)$domain=\(negations)"
            }
            return "\(body)$\(options),domain=\(negations)"
        }

        let rawDomains = parts[domainIndex]
            .dropFirst("domain=".count)
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let restricted = restrictDomainList(rawDomains, excluding: sites) else { return nil }
        parts[domainIndex] = "domain=" + restricted.joined.joined(separator: "|")
        let rule = "\(body)$\(parts.joined(separator: ","))"

        guard !restricted.uncoveredSubdomains.isEmpty,
              let companion = companionException(
                body: body, options: parts, domainIndex: domainIndex, sites: restricted.uncoveredSubdomains
              ) else {
            return rule
        }
        return rule + "\n" + companion
    }

    /// Safari cannot express "smth.com but not m.smth.com" on a network rule, so a
    /// blocking rule scoped to a parent domain is paired with an exception scoped
    /// to the excluded subdomains. Exception and badfilter rules have no inverse
    /// in the content blocker format and are left as they are.
    private static func companionException(
        body: String,
        options: [String],
        domainIndex: Int,
        sites: [String]
    ) -> String? {
        guard !body.hasPrefix("@@") else { return nil }
        if options.contains("badfilter") { return nil }

        var exceptionOptions = options
        exceptionOptions[domainIndex] = "domain=" + sites.joined(separator: "|")
        return "@@\(body)$\(exceptionOptions.joined(separator: ","))"
    }
}
