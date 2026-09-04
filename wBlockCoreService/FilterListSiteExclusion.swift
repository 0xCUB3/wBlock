//
//  FilterListSiteExclusion.swift
//  wBlockCoreService
//
//  Per-list site exclusions (issue #653). Safari content blocker rules from one
//  list are limited with unless-domain so other lists in the same blocker still
//  apply. Advanced rules get matching domain negations.
//

import Foundation

public enum FilterListSiteExclusion {
    public static func normalizedDomains(from raw: [String]) -> [String] {
        DisabledSitesNormalizer.normalizedDomains(from: raw)
    }

    public static func wildcardDomain(for site: String) -> String {
        let trimmed = site.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("*") ? trimmed : "*\(trimmed)"
    }

    /// Adds Safari `unless-domain` to every rule so this list does not apply on
    /// the excluded hosts. Other lists concatenated later remain unaffected.
    public static func applyingUnlessDomain(toJSON json: String, domains: [String]) -> String {
        let sites = normalizedDomains(from: domains)
        guard !sites.isEmpty else { return json }
        let wildcards = sites.map(wildcardDomain(for:))
        guard let data = json.data(using: .utf8),
              var rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return json
        }

        for index in rules.indices {
            var rule = rules[index]
            var trigger = rule["trigger"] as? [String: Any] ?? [:]
            var unlessDomain = trigger["unless-domain"] as? [String] ?? []
            for wildcard in wildcards where !unlessDomain.contains(wildcard) {
                unlessDomain.append(wildcard)
            }
            trigger["unless-domain"] = unlessDomain
            rule["trigger"] = trigger
            rules[index] = rule
        }

        guard let encoded = try? JSONSerialization.data(withJSONObject: rules, options: []) else {
            return json
        }
        return String(data: encoded, encoding: .utf8) ?? json
    }

    public static func concatenateContentBlockerJSON(_ chunks: [String]) -> String {
        var inners: [String] = []
        inners.reserveCapacity(chunks.count)
        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let open = trimmed.firstIndex(of: "["),
                  let close = trimmed.lastIndex(of: "]"),
                  open < close
            else { continue }
            let inner = trimmed[trimmed.index(after: open)..<close]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !inner.isEmpty {
                inners.append(String(inner))
            }
        }
        if inners.isEmpty { return "[]" }
        return "[" + inners.joined(separator: ",") + "]"
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
        if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("@@") {
            return line
        }

        if let cosmetic = splitCosmetic(trimmed) {
            return restrictCosmetic(cosmetic, excluding: sites) ?? ""
        }
        return restrictNetworkLine(trimmed, excluding: sites)
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

    private static func restrictCosmetic(
        _ cosmetic: (domains: String, separator: String, body: String),
        excluding sites: [String]
    ) -> String? {
        let rawDomains = cosmetic.domains
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if rawDomains.isEmpty {
            let negations = sites.map { "~\($0)" }.joined(separator: ",")
            return "\(negations)\(cosmetic.separator)\(cosmetic.body)"
        }

        let kept = rawDomains.filter { domain in
            let isNegated = domain.hasPrefix("~")
            let host = isNegated ? String(domain.dropFirst()) : domain
            if isNegated { return true }
            return !sites.contains { site in
                host == site || host.hasSuffix(".\(site)")
            }
        }
        if kept.isEmpty { return nil }
        return kept.joined(separator: ",") + cosmetic.separator + cosmetic.body
    }

    private static func restrictNetworkLine(_ line: String, excluding sites: [String]) -> String {
        let negations = sites.map { "~\($0)" }.joined(separator: "|")
        if let dollar = line.lastIndex(of: "$") {
            let body = String(line[..<dollar])
            var options = String(line[line.index(after: dollar)...])
            if let domainRange = options.range(of: "domain=") {
                let prefix = options[..<domainRange.upperBound]
                var valueAndRest = String(options[domainRange.upperBound...])
                let valueEnd = valueAndRest.firstIndex(of: ",") ?? valueAndRest.endIndex
                var value = String(valueAndRest[..<valueEnd])
                let rest = String(valueAndRest[valueEnd...])
                for site in sites {
                    let token = "~\(site)"
                    let parts = value.split(separator: "|").map(String.init)
                    if !parts.contains(token) {
                        value = value.isEmpty ? token : value + "|" + token
                    }
                }
                options = String(prefix) + value + rest
            } else if options.isEmpty {
                options = "domain=\(negations)"
            } else {
                options += ",domain=\(negations)"
            }
            return "\(body)$\(options)"
        }
        return "\(line)$domain=\(negations)"
    }
}
