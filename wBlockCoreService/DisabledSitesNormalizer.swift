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
        // Every site entry already covers its subdomains, so "*.example.com"
        // means the same as "example.com" (#870).
        if candidate.hasPrefix("*.") {
            candidate.removeFirst(2)
        }

        let range = NSRange(candidate.startIndex..., in: candidate)
        guard isIPv4Address(candidate)
            || hostnameRegex.firstMatch(in: candidate, options: [], range: range) != nil
        else { return nil }

        return candidate
    }

    /// Hostnames, including single-label and .local names on a LAN (#868). The last
    /// label must contain a letter so malformed dotted numbers fall to the IPv4 check.
    /// Compiled once; normalizedDomain runs for every entry whenever site lists are
    /// normalized, and compiling the pattern per call dominated that loop.
    private static let hostnameRegex = try! NSRegularExpression(
        pattern: #"^(?:[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)*(?=[a-z0-9\-]*[a-z])[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?$"#
    )

    private static func isIPv4Address(_ candidate: String) -> Bool {
        let octets = candidate.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { octet in
            (1...3).contains(octet.count)
                && octet.allSatisfy(\.isASCII) && octet.allSatisfy(\.isNumber)
                && (octet == "0" || octet.first != "0")
                && Int(octet).map { $0 <= 255 } == true
        }
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
