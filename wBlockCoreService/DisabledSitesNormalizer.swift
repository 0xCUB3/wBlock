import Foundation

public enum DisabledSitesNormalizer {
    public static func normalizedDomain(_ rawDomain: String) -> String? {
        let trimmed = rawDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let domainRegex =
            #"^(?:[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$"#
        guard trimmed.range(of: domainRegex, options: .regularExpression) != nil else {
            return nil
        }

        return trimmed
    }

    public static func normalizedDomains(from rawDomains: [String]) -> [String] {
        Array(Set(rawDomains.compactMap(normalizedDomain))).sorted()
    }
}
