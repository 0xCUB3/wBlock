import Foundation

@main
struct DisabledSitesNormalizationTests {
    static func main() {
        let normalized = DisabledSitesNormalizer.normalizedDomains(
            from: [
                " Example.com ",
                "www.Example.com",
                "sub.example.com",
                "EXAMPLE.com",
                "",
                "invalid domain",
                "example.com",
            ]
        )

        expectEqual(
            normalized,
            [
                "example.com",
                "sub.example.com",
                "www.example.com",
            ],
            "expected trimmed, lowercased, unique, sorted valid domains"
        )

        let single = DisabledSitesNormalizer.normalizedDomain(" WWW.Clubic.COM ")
        expectEqual(single, "www.clubic.com", "expected single domain normalization")

        let invalid = DisabledSitesNormalizer.normalizedDomain("not a host/path")
        expectEqual(invalid, nil, "expected invalid domain to be rejected")

        print("ok")
    }

    private static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: String
    ) {
        guard actual == expected else {
            fputs("FAIL: \(message)\nactual: \(actual)\nexpected: \(expected)\n", stderr)
            exit(1)
        }
    }
}
