
import Foundation

@main
struct UserStyleParsingAndMatchingTests {
    static func main() {
        testDetectionAndMetadata()
        testSectionParsingAndMatching()
        testEffectiveCSSAssembly()
        testVariableResolution()
        testUserScriptIntegration()
        testURLSupport()
        print("PASS: userstyle parsing and matching")
    }

    static let sampleStyle = """
    /* ==UserStyle==
    @name           Example Dark
    @namespace      example.com
    @version        1.2.3
    @description    Makes example.com dark.
    @updateURL      https://example.com/styles/dark.user.css
    ==/UserStyle== */

    :root { color-scheme: dark; }

    @-moz-document domain("example.com"), url-prefix("https://app.example.net/dash") {
        body { background: #111 !important; }
        @media (max-width: 600px) {
            body { font-size: 14px; }
        }
        .brace-string::before { content: "}"; }
        /* a comment with a sneaky } brace */
    }

    @-moz-document regexp("https://docs\\\\.example\\\\.org/.*") {
        main { max-width: 80ch; }
    }

    @-moz-document url("https://exact.example.com/page") {
        h1 { display: none; }
    }
    """

    static func testDetectionAndMetadata() {
        expect(UserStyleSupport.isUserStyleContent(sampleStyle), "sample should be detected as userstyle")
        expect(!UserStyleSupport.isUserStyleContent("// ==UserScript==\n// ==/UserScript=="), "userscript is not a userstyle")
        expect(!UserStyleSupport.isUserStyleContent("body {}"), "plain css is not a userstyle")

        guard let parsed = UserStyleSupport.parsed(from: sampleStyle) else {
            return fail("sample style should parse")
        }
        expectEqual(parsed.name ?? "", "Example Dark", "name should parse")
        expectEqual(parsed.version ?? "", "1.2.3", "version should parse")
        expectEqual(parsed.description ?? "", "Makes example.com dark.", "description should parse")
        expectEqual(parsed.updateURL ?? "", "https://example.com/styles/dark.user.css", "updateURL should parse")
        expectEqual(parsed.preprocessor, "default", "missing preprocessor defaults to default")
        expect(parsed.isPreprocessorSupported, "default preprocessor should be supported")

        let less = """
        /* ==UserStyle==
        @name Less Style
        @preprocessor less
        ==/UserStyle== */
        """
        guard let lessParsed = UserStyleSupport.parsed(from: less) else {
            return fail("less style should still parse")
        }
        expect(!lessParsed.isPreprocessorSupported, "less preprocessor should be unsupported")
        expect(UserStyleSupport.isPreprocessorSupported("uso"), "uso preprocessor should be supported")
    }

    static func testSectionParsingAndMatching() {
        guard let parsed = UserStyleSupport.parsed(from: sampleStyle) else {
            return fail("sample style should parse")
        }

        expectEqual(parsed.sections.count, 3, "should find three @-moz-document sections")
        expect(parsed.hasGlobalCSSForTesting, "global css should be captured")
        expect(parsed.globalCSS.contains("color-scheme: dark"), "global css should keep content")
        expect(!parsed.globalCSS.contains("background: #111"), "section css must not leak into global")

        let first = parsed.sections[0]
        expectEqual(first.conditions.count, 2, "first section should have two conditions")
        expect(first.css.contains("@media (max-width: 600px)"), "nested at-rule should stay inside section")
        expect(first.css.contains("content: \"}\""), "string braces should not end the section")
        expect(first.css.contains("sneaky } brace"), "comment braces should not end the section")
        expect(first.matches(url: "https://example.com/"), "domain condition should match apex")
        expect(first.matches(url: "https://www.example.com/x"), "domain condition should match subdomain")
        expect(!first.matches(url: "https://notexample.com/"), "domain condition must not match suffix lookalike")
        expect(first.matches(url: "https://app.example.net/dashboard"), "url-prefix should match")
        expect(!first.matches(url: "https://app.example.net/other"), "url-prefix must not match different path")

        let second = parsed.sections[1]
        expect(second.matches(url: "https://docs.example.org/guide"), "regexp should match entire URL")
        expect(!second.matches(url: "https://docs.example.org"), "regexp must require full match")
        expect(!second.matches(url: "https://prefix.docs.example.org/guide"), "regexp is anchored at start")

        let third = parsed.sections[2]
        expect(third.matches(url: "https://exact.example.com/page"), "url condition should match exactly")
        expect(!third.matches(url: "https://exact.example.com/page2"), "url condition must not match longer URL")

        // Persistence round-trip through serialized conditions.
        let serialized = parsed.serializedConditions
        expect(serialized.contains("global"), "global token should be serialized")
        expect(serialized.contains("domain:example.com"), "domain condition should be serialized")
        expect(serialized.contains("url-prefix:https://app.example.net/dash"), "url-prefix should be serialized")
        expect(UserStyleSupport.matches(serializedConditions: serialized, url: "https://anything.invalid/"), "global style applies everywhere")

        let sectionOnly = serialized.filter { $0 != "global" }
        expect(UserStyleSupport.matches(serializedConditions: sectionOnly, url: "https://example.com/"), "serialized domain should match")
        expect(!UserStyleSupport.matches(serializedConditions: sectionOnly, url: "https://unrelated.invalid/"), "serialized conditions must not match unrelated URL")
    }

    static func testEffectiveCSSAssembly() {
        guard let css = UserStyleSupport.effectiveCSS(forContent: sampleStyle, url: "https://example.com/") else {
            return fail("effective css should exist for matching URL")
        }
        expect(css.contains("color-scheme: dark"), "effective css should include global css")
        expect(css.contains("background: #111"), "effective css should include matching section")
        expect(!css.contains("max-width: 80ch"), "effective css must exclude non-matching section")
        expect(!css.contains("@-moz-document"), "effective css must not contain @-moz-document wrappers")
        expect(!css.contains("==UserStyle=="), "effective css must not contain the metadata block")

        guard let unrelated = UserStyleSupport.effectiveCSS(forContent: sampleStyle, url: "https://unrelated.invalid/") else {
            return fail("global css should still apply on unrelated URL")
        }
        expect(unrelated.contains("color-scheme: dark"), "global css applies everywhere")
        expect(!unrelated.contains("background: #111"), "sections must not apply on unrelated URL")

        let sectionOnlyStyle = """
        /* ==UserStyle==
        @name Sections Only
        ==/UserStyle== */
        @-moz-document domain("example.com") {
            body { margin: 0; }
        }
        """
        expect(
            UserStyleSupport.effectiveCSS(forContent: sectionOnlyStyle, url: "https://other.invalid/") == nil,
            "no css should be produced when nothing matches"
        )

        // USO-archive styles often carry decorative comment headers outside their
        // sections; comments alone must not make a style global.
        let commentHeaderStyle = """
        /* ==UserStyle==
        @name Comment Header
        ==/UserStyle== */
        /** Theme: Zesty ashes — By: HexD **/
        @-moz-document domain("example.com") {
            body { margin: 0; }
        }
        """
        guard let commentParsed = UserStyleSupport.parsed(from: commentHeaderStyle) else {
            return fail("comment header style should parse")
        }
        expect(
            !commentParsed.serializedConditions.contains("global"),
            "comment-only global css must not serialize the global token"
        )
        expect(
            UserStyleSupport.effectiveCSS(forContent: commentHeaderStyle, url: "https://other.invalid/") == nil,
            "comment-only global css must not apply anywhere"
        )
        guard let commentCSS = UserStyleSupport.effectiveCSS(forContent: commentHeaderStyle, url: "https://example.com/") else {
            return fail("comment header style should still apply on its domain")
        }
        expect(commentCSS.contains("margin: 0"), "matching section still applies with comment header")

        expect(UserStyleSupport.containsMeaningfulCSS("/**/x"), "content after a tight comment is meaningful")
        expect(!UserStyleSupport.containsMeaningfulCSS("/* a */ \n\t /* b */"), "comments and whitespace are not meaningful")
        expect(!UserStyleSupport.containsMeaningfulCSS("/* unterminated"), "unterminated comment is not meaningful")

        // @namespace preambles (typical of USO conversions) must not make a style
        // global, but must ship with matching sections for namespaced selectors.
        let namespaceStyle = """
        /* ==UserStyle==
        @name Namespace Preamble
        ==/UserStyle== */
        @namespace url(http://www.w3.org/1999/xhtml);
        @-moz-document domain("example.com") {
            body { margin: 0; }
        }
        """
        guard let nsParsed = UserStyleSupport.parsed(from: namespaceStyle) else {
            return fail("namespace style should parse")
        }
        expect(!nsParsed.serializedConditions.contains("global"), "namespace-only preamble must not be global")
        expect(
            UserStyleSupport.effectiveCSS(forContent: namespaceStyle, url: "https://other.invalid/") == nil,
            "namespace-only preamble must not apply anywhere"
        )
        guard let nsCSS = UserStyleSupport.effectiveCSS(forContent: namespaceStyle, url: "https://example.com/") else {
            return fail("namespace style should apply on its domain")
        }
        expect(nsCSS.contains("@namespace url(http://www.w3.org/1999/xhtml);"), "namespace declaration must ship with sections")
        expect(nsCSS.contains("margin: 0"), "section css must ship alongside namespace")
    }

    static func testVariableResolution() {
        let defaultPreprocessor = """
        /* ==UserStyle==
        @name Vars
        @var color accent "Accent color" #ff0040
        @var checkbox compact "Compact mode" 1
        @var text brand 'Brand' "wBlock"
        @var range fontSize "Font size" [14, 8, 30, 1, "px"]
        @var select theme "Theme" {
            "Light": "light",
            "Dark*": "dark"
        }
        ==/UserStyle== */
        body { color: var(--accent); }
        """
        guard let css = UserStyleSupport.effectiveCSS(forContent: defaultPreprocessor, url: "https://x.invalid/") else {
            return fail("vars style should produce css")
        }
        expect(css.contains("--accent: #ff0040;"), "color var should resolve")
        expect(css.contains("--compact: 1;"), "checkbox var should resolve")
        expect(css.contains("--brand: wBlock;"), "text var should be unquoted")
        expect(css.contains("--fontSize: 14px;"), "range var should fold units")
        expect(css.contains("--theme: dark;"), "select var should pick starred default")
        expect(css.hasPrefix(":root {"), "default preprocessor should emit :root prelude first")

        let uso = """
        /* ==UserStyle==
        @name USO Vars
        @preprocessor uso
        @advanced dropdown layout "Layout" {
            wide "Wide*" <<<EOT
        main { width: 100%; } EOT;
            narrow "Narrow" <<<EOT
        main { width: 60ch; } EOT;
        }
        @advanced color bg "Background" #222222
        @advanced image hero "Hero" {
            hero1 "First*" "https://example.com/hero.png"
        }
        ==/UserStyle== */
        /*[[layout]]*/
        body { background: /*[[bg]]*/; background-image: url(/*[[hero]]*/); }
        /*[[missing]]*/
        """
        guard let usoCSS = UserStyleSupport.effectiveCSS(forContent: uso, url: "https://x.invalid/") else {
            return fail("uso style should produce css")
        }
        expect(usoCSS.contains("main { width: 100%; }"), "uso dropdown default should substitute")
        expect(!usoCSS.contains("width: 60ch"), "non-default dropdown option must not appear")
        expect(usoCSS.contains("background: #222222;"), "uso color placeholder should substitute")
        expect(usoCSS.contains("url(https://example.com/hero.png)"), "uso image placeholder should substitute")
        expect(usoCSS.contains("/*[[missing]]*/"), "unknown placeholders stay as harmless comments")
        expect(!usoCSS.contains(":root {"), "uso preprocessor must not emit :root prelude")
    }

    static func testUserScriptIntegration() {
        var style = UserScript(name: "fallback", content: sampleStyle)
        style.parseMetadata()

        expect(style.isUserStyle, "parseMetadata should detect userstyle content")
        expectEqual(style.name, "Example Dark", "style name should come from metadata")
        expectEqual(style.version, "1.2.3", "style version should come from metadata")
        expectEqual(style.runAt, "document-start", "styles should run at document-start")
        expectEqual(style.updateURL ?? "", "https://example.com/styles/dark.user.css", "style updateURL should persist")
        expect(style.grant.isEmpty && style.require.isEmpty, "styles should not carry script directives")

        expect(style.matches(url: "https://example.com/"), "style should match via serialized conditions")
        expect(style.matches(url: "https://unrelated.invalid/"), "global css should match everywhere")

        var sectionOnly = UserScript(
            name: "x",
            content: """
            /* ==UserStyle==
            @name Scoped
            @version 1.0.0
            ==/UserStyle== */
            @-moz-document domain("example.com") {
                body { margin: 0; }
            }
            """
        )
        sectionOnly.parseMetadata()
        expect(sectionOnly.isUserStyle, "scoped style should be detected")
        expect(sectionOnly.matches(url: "https://example.com/a"), "scoped style should match its domain")
        expect(!sectionOnly.matches(url: "https://other.invalid/"), "scoped style must not match elsewhere")

        // Re-parsing as a script must clear the style flag (idempotent parseMetadata).
        var script = UserScript(
            name: "s",
            content: "// ==UserScript==\n// @name JS\n// @match *://example.com/*\n// ==/UserScript==\nconsole.log(1);"
        )
        script.parseMetadata()
        expect(!script.isUserStyle, "userscript must not be flagged as style")

        // A userscript embedding the UserStyle marker in a string stays a script.
        var tricky = UserScript(
            name: "t",
            content: "// ==UserScript==\n// @name Tricky\n// ==/UserScript==\nconst s = \"/* ==UserStyle== */ ==/UserStyle==\";"
        )
        tricky.parseMetadata()
        expect(!tricky.isUserStyle, "userscript metadata block wins over embedded markers")
    }

    static func testURLSupport() {
        expect(
            UserScriptURLSupport.validatedRemoteURL(from: "https://example.com/styles/dark.user.css") != nil,
            ".user.css remote URLs should validate"
        )
        expect(
            UserScriptURLSupport.validatedRemoteURL(from: "https://example.com/styles/site.css") != nil,
            ".css remote URLs should validate"
        )
        expect(
            UserScriptURLSupport.validatedRemoteURL(from: "https://example.com/styles/dark.scss") == nil,
            "unrelated extensions must not validate"
        )
        expectEqual(
            UserScriptURLSupport.displayName(forFilename: "dark.user.css"),
            "dark",
            "display name should strip .user.css"
        )
        expectEqual(
            UserScriptURLSupport.displayName(forFilename: "site.css"),
            "site",
            "display name should strip .css"
        )
    }

    private static func fail(_ message: String) {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
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

extension UserStyleSupport.ParsedStyle {
    var hasGlobalCSSForTesting: Bool {
        !globalCSS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
