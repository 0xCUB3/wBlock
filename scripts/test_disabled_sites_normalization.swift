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

        let urlInputs: [(String, String?)] = [
            ("https://link-center.net", "link-center.net"),
            ("HTTPS://Link-Center.NET/", "link-center.net"),
            ("http://example.com/path?q=1#frag", "example.com"),
            ("example.com:8080/path", "example.com"),
            ("user:pass@example.com", "example.com"),
            ("https://", nil),
            ("https://127.0.0.1/", nil),
        ]
        for (input, expected) in urlInputs {
            expectEqual(
                DisabledSitesNormalizer.normalizedDomain(input),
                expected,
                "expected URL input \(input) to normalize to \(expected ?? "nil")"
            )
        }

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
