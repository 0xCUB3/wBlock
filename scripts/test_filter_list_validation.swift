import Foundation

@main
struct FilterListValidationTests {
    static func main() {
        expectValidURL("https://example.com/filter.txt", "expected .txt filter URLs to be accepted")
        expectValidURL("https://example.com/subscriptions/filter", "expected extensionless filter URLs to remain accepted")
        expectInvalidURL("https://example.com/script.user.js", "expected .user.js URLs to be rejected as filters")
        expectInvalidURL(
            "https://testcases.agrd.dev/Userscripts/GMapiV4Tester/GMapi_v4-tester.user.js",
            "expected the GMapi tester userscript URL to be rejected as a filter"
        )
        expectInvalidURL("https://example.com/script.js", "expected .js URLs to be rejected as filters")
        expectInvalidURL("ftp://example.com/filter.txt", "expected non-http(s) URLs to be rejected")

        expectParsedURLs(
            """
            https://example.com/one.txt
            https://example.com/two.list
            """,
            expected: ["https://example.com/one.txt", "https://example.com/two.list"],
            invalidLineNumbers: [],
            "expected newline-separated filter URLs to be parsed"
        )
        expectParsedURLs(
            "\r\n<https://example.com/filter.txt?parts=one,two;three>\r\n\r\nhttps://example.com/filter.txt?parts=one,two;three",
            expected: ["https://example.com/filter.txt?parts=one,two;three"],
            invalidLineNumbers: [],
            "expected CRLF, blank lines, URL punctuation, wrappers, and duplicates to be handled"
        )
        expectParsedURLs(
            "https://example.com/Filter.txt\nhttps://example.com/filter.txt\nnot-a-url\nhttps://example.com/script.user.js",
            expected: ["https://example.com/Filter.txt", "https://example.com/filter.txt"],
            invalidLineNumbers: [3, 4],
            "expected exact URL identity and invalid line numbers to be preserved"
        )

        expectValidContent(
            """
            ! Title: Test List
            ||example.com^
            """,
            "expected ordinary Adblock syntax to be accepted"
        )
        expectValidContent(
            """
            [Adblock Plus]
            ! Title: Referral Allowlist
            @@||example.com^
            """,
            "expected allowlist-only exception rules to be accepted"
        )
        expectInvalidContent(
            """
            // ==UserScript==
            // @name GMapi V4 Tester
            // @match *://*/*
            // ==/UserScript==
            console.log('not a filter');
            """,
            "expected userscript metadata blocks to be rejected as filters"
        )
        expectInvalidContent("<html><body>challenge</body></html>", "expected HTML to be rejected")

        print("PASS")
    }

    private static func expectValidURL(_ rawURL: String, _ message: String) {
        guard FilterListURLSupport.validatedRemoteURL(from: rawURL) != nil else {
            fail(message)
        }
    }

    private static func expectInvalidURL(_ rawURL: String, _ message: String) {
        guard FilterListURLSupport.validatedRemoteURL(from: rawURL) == nil else {
            fail(message)
        }
    }

    private static func expectParsedURLs(
        _ input: String,
        expected: [String],
        invalidLineNumbers: [Int],
        _ message: String
    ) {
        let result = FilterListURLSupport.parseRemoteURLs(from: input)
        guard result.urls.map(\.absoluteString) == expected,
              result.invalidLineNumbers == invalidLineNumbers else {
            fail(message)
        }
    }

    private static func expectValidContent(_ content: String, _ message: String) {
        guard FilterListContentValidator.appearsToBeFilterList(content) else {
            fail(message)
        }
    }

    private static func expectInvalidContent(_ content: String, _ message: String) {
        guard !FilterListContentValidator.appearsToBeFilterList(content) else {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
