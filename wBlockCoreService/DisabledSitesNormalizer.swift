import Foundation

public enum DisabledSitesNormalizer {
    public static func normalizedDomain(_ rawDomain: String) -> String? {
        var candidate = rawDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !candidate.isEmpty else { return nil }

        // Accept full URLs by reducing them to their host: strip the scheme,
        // path/query/fragment, credentials, and port.
        if let schemeRange = candidate.range(of: "://") {
            candidate = String(candidate[schemeRange.upperBound...])
        }
        if let separator = candidate.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            candidate = String(candidate[..<separator])
        }
        if let credentialsEnd = candidate.lastIndex(of: "@") {
            candidate = String(candidate[candidate.index(after: credentialsEnd)...])
        }
        if let portStart = candidate.firstIndex(of: ":") {
            candidate = String(candidate[..<portStart])
        }

        let domainRegex =
            #"^(?:[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$"#
        guard candidate.range(of: domainRegex, options: .regularExpression) != nil else {
            return nil
        }

        return candidate
    }

    public static func normalizedDomains(from rawDomains: [String]) -> [String] {
        Array(Set(rawDomains.compactMap(normalizedDomain))).sorted()
    }

    public static func effectiveFilterDisabledDomains(
        master: [String],
        filterOnly: [String]
    ) -> [String] {
        normalizedDomains(from: master + filterOnly)
    }
}
