import Foundation

@main
struct UserScriptContentValidationTests {
    static func main() {
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
        print("PASS: source keywords accepted; HTML protection pages rejected")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
