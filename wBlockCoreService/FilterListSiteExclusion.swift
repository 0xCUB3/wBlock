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

    private static let cosmeticSeparators = ["#@?#", "#@$#", "#?#", "#$#", "#@#", "##"]

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
}
