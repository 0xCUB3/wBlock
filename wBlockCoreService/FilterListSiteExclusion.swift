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
//  removing the excluded ones instead of appending negations.
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

    /// Narrows a domain list so it never matches an excluded site.
    /// Returns nil when the rule was scoped to sites that are all excluded.
    private static func restrictDomainList(_ domains: [String], excluding sites: [String]) -> [String]? {
        let positives = domains.filter { !$0.hasPrefix("~") }
        var negatives = domains.filter { $0.hasPrefix("~") }

        if positives.isEmpty {
            for site in sites where !negatives.contains("~\(site)") {
                negatives.append("~\(site)")
            }
            return negatives
        }

        let kept = positives.filter { host in
            !sites.contains { site in host == site || host.hasSuffix(".\(site)") }
        }
        if kept.isEmpty { return nil }
        return kept + negatives
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
        return restricted.joined(separator: ",") + cosmetic.separator + cosmetic.body
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
        parts[domainIndex] = "domain=" + restricted.joined(separator: "|")
        return "\(body)$\(parts.joined(separator: ","))"
    }
    /// Intersects a rule's existing domain scope with the pause exception sites.
    public static func restrictingRules(_ text: String, to domains: [String]) -> String {
        let allowed = normalizedDomains(from: domains)
        guard !allowed.isEmpty else { return "" }
        func intersect(_ original: [String]) -> [String]? {
            let positives = original.filter { !$0.hasPrefix("~") }
            let negatives = original.filter { $0.hasPrefix("~") }
            var candidates = positives.isEmpty ? allowed : positives.flatMap { original in
                allowed.compactMap { site -> String? in
                    if original == site || original.hasSuffix("." + site) { return original }
                    if site.hasSuffix("." + original) { return site }
                    return nil
                }
            }
            candidates.removeAll { candidate in
                negatives.contains { excluded in
                    let site = String(excluded.dropFirst())
                    return candidate == site || candidate.hasSuffix("." + site)
                }
            }
            guard !candidates.isEmpty else { return nil }
            let relevantNegatives = negatives.filter { excluded in
                let domain = String(excluded.dropFirst())
                return candidates.contains { domain.hasSuffix("." + $0) }
            }
            return Array(Set(candidates)).sorted() + relevantNegatives
        }
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { raw in
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[Adblock") { return line }
            if let cosmetic = splitCosmetic(line) {
                let domains = cosmetic.domains.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let scope = intersect(domains) else { return "" }
                return scope.joined(separator: ",") + cosmetic.separator + cosmetic.body
            }
            let optionStart: String.Index?
            let pattern = line.hasPrefix("@@") ? line.dropFirst(2) : line[...]
            if pattern.hasPrefix("/"), let closing = pattern.dropFirst().lastIndex(of: "/") {
                let next = line.index(after: closing)
                optionStart = next < line.endIndex && line[next] == "$" ? next : nil
            } else {
                optionStart = line.lastIndex(of: "$")
            }
            let body = optionStart.map { String(line[..<$0]) } ?? line
            var options = optionStart.map { line[line.index(after: $0)...].split(separator: ",").map(String.init) } ?? []
            let index = options.firstIndex { $0.hasPrefix("domain=") }
            let original = index.map { options[$0].dropFirst(7).split(separator: "|").map(String.init) } ?? []
            guard let scope = intersect(original) else { return "" }
            let option = "domain=" + scope.joined(separator: "|")
            if let index { options[index] = option } else { options.append(option) }
            return body + "$" + options.joined(separator: ",")
        }.joined(separator: "\n")
    }

    public static func applyingSiteRestrictions(_ text: String, for filter: FilterList) -> String {
        let excluded = restrictingAdvancedRules(text, excluding: filter.excludedSites)
        guard let sites = filter.activeSiteRestriction else { return excluded }
        return restrictingRules(excluded, to: sites)
    }

}
