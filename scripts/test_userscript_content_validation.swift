import Foundation

@main
struct UserScriptContentValidationTests {
    static func main() throws {
        for phrase in ["ddos-guard", "ddos protection", "checking your browser", "challenge"] {
            let sources = [
                "// ==UserScript==\n// @name Example\n// ==/UserScript==\nconst marker = '\(phrase)';",
                "/* \(phrase) */\nbody::before { content: '\(phrase)'; }",
                "{\"message\":\"\(phrase)\"}",
                "const template = `<!doctype html><html>\(phrase)</html>`;",
                phrase
            ]
            for source in sources {
                expect(!UserScriptContentValidation.isProtectionPage(source),
                       "source mentioning '\(phrase)' is not a challenge document")
            }
            for root in ["<!doctype html><html>", "<HTML lang='en'>", "<head>", "<body>"] {
                for preamble in ["", "\u{FEFF}\n \t", "<!-- generated response -->\n",
                                 " \n<!-- one --><!-- two -->\n", "<?xml version='1.0'?>\n"] {
                    let expected = phrase != "challenge" || root.hasPrefix("<!doctype")
                    expect(UserScriptContentValidation.isProtectionPage("\(preamble)\(root)\(phrase)</html>") == expected,
                           "HTML documents should retain the existing marker rules")
                }
            }
        }
        for source in ["", " \n", "<!doctype html><html><body>Ordinary resource</body></html>",
                       "<htmlish>checking your browser", "<!-- checking your browser",
                       "<!-- comment -->\nconst marker = 'ddos-guard';"] {
            expect(!UserScriptContentValidation.isProtectionPage(source),
                   "non-challenge content must not match")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let responseFile = root.appendingPathComponent("response.user.js")
        for source in ["const template = `<!doctype html><html>challenge</html>`;",
                       "// ==UserScript==\n// @name Example\n// ==/UserScript==\nalert('ok');",
                       "/* ==UserStyle== */\nbody { color: red; }"] {
            try Data(source.utf8).write(to: responseFile, options: .atomic)
            let validated = try UserScriptContentValidation.downloadedSource(from: Data(contentsOf: responseFile))
            expect(validated == source, "valid source must retain its exact bytes")
        }
        for preamble in ["", "\u{FEFF}\n ", "<!-- response -->\n", "<?xml version='1.0'?>\n"] {
            for html in ["<!doctype html><html><title>Sign in</title></html>",
                         "<HTML lang='en'><body>Unavailable</body></HTML>",
                         "<head><title>Moved</title></head>", "<body>ddos-guard</body>"] {
                expectRejected(Data((preamble + html).utf8))
            }
        }
        for data in [Data(), Data(" \n\t".utf8), Data([0xff, 0xfe])] { expectRejected(data) }
        print("PASS: source keywords and HTML resources accepted; invalid script documents rejected")
    }

    private static func expectRejected(_ data: Data) {
        do {
            _ = try UserScriptContentValidation.downloadedSource(from: data)
            expect(false, "invalid response must not become script source")
        } catch {
            expect((error as? URLError)?.code == .cannotParseResponse, "existing parse error must be preserved")
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
