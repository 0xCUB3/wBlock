//
// scripts/test_include_resolver_url_encoding.swift
//
// Regression coverage for !#include path resolution: pre-percent-encoded
// relative paths must not be double-encoded by Foundation.
//
// Run via:
//   swiftc -parse-as-library \
//     wBlockCoreService/IncludeResolver.swift \
//     wBlockCoreService/ConditionalEvaluator.swift \
//     wBlockCoreService/PlatformConstants.swift \
//     scripts/test_include_resolver_url_encoding.swift \
//     -o /tmp/include_url_test && /tmp/include_url_test
//
// Prints `PASS` on success, `FAIL: <message>` (exit 1) on the first divergence.
//

import Foundation

@main
struct IncludeResolverURLEncodingTests {
    static func main() {
        let base = URL(string: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/")!

        // The live LegitimateURLShortener include path (spaces pre-encoded, em dash raw).
        expectResolved(
            "uBO%20list%20extensions/LegitimateURLShortener%20—%20AdGuardOnlyEntries.txt",
            relativeTo: base,
            equals: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/uBO%20list%20extensions/LegitimateURLShortener%20%E2%80%94%20AdGuardOnlyEntries.txt",
            "pre-encoded spaces must not become %2520"
        )

        // Same path fully decoded (spaces + em dash as unicode).
        expectResolved(
            "uBO list extensions/LegitimateURLShortener — AdGuardOnlyEntries.txt",
            relativeTo: base,
            equals: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/uBO%20list%20extensions/LegitimateURLShortener%20%E2%80%94%20AdGuardOnlyEntries.txt",
            "decoded relative paths still encode once"
        )

        // Fully percent-encoded form including the em dash.
        expectResolved(
            "uBO%20list%20extensions/LegitimateURLShortener%20%E2%80%94%20AdGuardOnlyEntries.txt",
            relativeTo: base,
            equals: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/uBO%20list%20extensions/LegitimateURLShortener%20%E2%80%94%20AdGuardOnlyEntries.txt",
            "fully percent-encoded include paths must decode then re-encode once"
        )

        expectResolved(
            "subdir/file.txt",
            relativeTo: base,
            equals: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/subdir/file.txt",
            "plain relative paths still resolve"
        )

        expectResolved(
            "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/other.txt",
            relativeTo: base,
            equals: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/other.txt",
            "absolute same-host includes still resolve"
        )

        // Empty / whitespace-only paths are rejected.
        if IncludeResolver.resolveSublistURL(path: "   ", relativeTo: base) != nil {
            fail("whitespace-only include path must be rejected")
        }
        if IncludeResolver.resolveSublistURL(path: "", relativeTo: base) != nil {
            fail("empty include path must be rejected")
        }

        // The pre-fix double-encoded form must not be produced for the live include.
        let liveInclude = "uBO%20list%20extensions/LegitimateURLShortener%20—%20AdGuardOnlyEntries.txt"
        guard let liveURL = IncludeResolver.resolveSublistURL(path: liveInclude, relativeTo: base) else {
            fail("live LegitimateURLShortener include must resolve")
        }
        if liveURL.absoluteString.contains("%2520") {
            fail("resolved include must not contain double-encoded %2520: \(liveURL.absoluteString)")
        }

        print("PASS")
    }

    private static func expectResolved(
        _ path: String,
        relativeTo base: URL,
        equals expected: String,
        _ message: String
    ) {
        guard let url = IncludeResolver.resolveSublistURL(path: path, relativeTo: base) else {
            fail("\(message): resolve returned nil for \(path)")
        }
        guard url.absoluteString == expected else {
            fail("\(message): got \(url.absoluteString), expected \(expected)")
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
