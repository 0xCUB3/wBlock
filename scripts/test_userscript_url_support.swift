import Foundation

@main
struct UserScriptURLSupportTests {
    static func main() {
        expectValid(
            "https://example.com/script.js",
            expectedPath: "/script.js",
            "expected plain .js remote userscript URLs to be accepted"
        )
        expectValid(
            "https://example.com/script.user.js",
            expectedPath: "/script.user.js",
            "expected .user.js remote userscript URLs to still be accepted"
        )
        expectInvalid(
            "https://example.com/script.txt",
            "expected non-JavaScript remote URLs to be rejected"
        )
        expectInvalid(
            "ftp://example.com/script.js",
            "expected non-http(s) remote URLs to be rejected"
        )
        expectValid(
            "https://example.com/raw?file=script.user.js",
            expectedPath: "/raw",
            "expected userscript URLs with the filename in a query parameter to be accepted"
        )
        expectValid(
            "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=userscript/bpc.en.user.js",
            expectedPath: "/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw",
            "expected the gitflic BPC userscript URL (#455) to be accepted"
        )
        expectInvalid(
            "https://example.com/raw?file=script.txt",
            "expected query-parameter URLs without a supported extension to be rejected"
        )

        let plainName = UserScriptURLSupport.displayName(forRemoteURL: URL(string: "https://example.com/foo.js")!)
        expectEqual(plainName, "foo", "expected .js suffix to be stripped from remote display names")

        expectEqual(
            UserScriptURLSupport.normalizePastedURL("\nhttps://example.com/script.user.js\n\n"),
            "https://example.com/script.user.js",
            "expected extra blank lines around a pasted script URL to be stripped"
        )
        expectEqual(
            UserScriptURLSupport.normalizePastedURL("""
            https://greasyfork.org/scripts/123-very-long-name/
            script.user.js
            """),
            "https://greasyfork.org/scripts/123-very-long-name/script.user.js",
            "expected a wrapped pasted script URL to be rejoined"
        )

        let bulkURLs = "https://example.com/one.user.js\nhttps://example.com/two.user.js"
        expectEqual(
            UserScriptURLSupport.normalizePastedURL(bulkURLs),
            bulkURLs,
            "expected complete bulk URLs to remain on separate lines"
        )
        expectEqual(
            UserScriptURLSupport.parseRemoteURLs(from: bulkURLs).map(\.lastPathComponent),
            ["one.user.js", "two.user.js"],
            "expected both complete bulk URLs to be parsed"
        )
        expectEqual(
            UserScriptURLSupport.parseRemoteURLs(
                from: "https://example.com/wrapped/\nscript.user.js"
            ).map(\.lastPathComponent),
            ["script.user.js"],
            "expected a wrapped single URL to be rejoined and parsed"
        )
        expectEqual(
            UserScriptURLSupport.parseRemoteURLs(
                from: "https://example.com/one.user.js\nnot a URL"
            ),
            [],
            "expected mixed valid and invalid lines to be rejected"
        )

        expectValid(
            "\nhttps://example.com/script.user.js\n",
            expectedPath: "/script.user.js",
            "expected script URL validation to accept a pasted URL with surrounding newlines"
        )

        let userScriptName = UserScriptURLSupport.displayName(
            forRemoteURL: URL(string: "https://example.com/foo.user.js")!
        )
        expectEqual(
            userScriptName,
            "foo",
            "expected .user.js suffix to be stripped from remote display names"
        )

        print("PASS")
    }

    private static func expectValid(_ rawURL: String, expectedPath: String, _ message: String) {
        guard let url = UserScriptURLSupport.validatedRemoteURL(from: rawURL) else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }

        expectEqual(url.path, expectedPath, message)
    }

    private static func expectInvalid(_ rawURL: String, _ message: String) {
        guard UserScriptURLSupport.validatedRemoteURL(from: rawURL) == nil else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fputs("FAIL: \(message)\nactual: \(actual)\nexpected: \(expected)\n", stderr)
            exit(1)
        }
    }
}
