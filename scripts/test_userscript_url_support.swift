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

        let plainName = UserScriptURLSupport.displayName(forRemoteURL: URL(string: "https://example.com/foo.js")!)
        expectEqual(plainName, "foo", "expected .js suffix to be stripped from remote display names")

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
