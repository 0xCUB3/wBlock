
import Foundation

@main
struct UserStyleParsingAndMatchingTests {
    static func main() {
#if DEBUG
        let resources = [
            ("less.min", "WBLOCK_LESS_BUNDLE"),
            ("wblock-sass-1.102.0.min", "WBLOCK_SASS_BUNDLE"),
            ("stylus-jsc", "WBLOCK_STYLUS_BUNDLE"),
            ("wblock-postcss-nested", "WBLOCK_POSTCSS_BUNDLE")
        ]
        var overrides: [String: String] = [:]
        for (name, variable) in resources {
            guard let path = ProcessInfo.processInfo.environment[variable],
                  let bundle = try? String(contentsOfFile: path, encoding: .utf8) else {
                return fail("\(variable) must point to the vendored \(name) bundle")
            }
            overrides[name] = bundle
        }
        UserStyleCompiler.compilerSourceOverrides = overrides
#endif
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            testDetectionAndMetadata()
            testSectionParsingAndMatching()
            testEffectiveCSSAssembly()
            testVariableResolution()
            testLessCompilation()
            testCompiledStyleCacheAndArtifactIdentity()
            testUserScriptIntegration()
            testURLSupport()
            testRemoteImportInlining()
            finished.signal()
        }
        while finished.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
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
        expect(lessParsed.isPreprocessorSupported, "less preprocessor should be supported")
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

    static func testLessCompilation() {
        let less = """
        /* ==UserStyle==
        @name Less compilation
        @preprocessor less
        @var color accent "Accent" #e91e63
        @var text label "Label" "wBlock"
        ==/UserStyle== */
        @outside: red;
        .outside-mixin() { border: 1px solid blue; }
        @-moz-document domain("example.com") {
            .card {
                color: @accent;
                content: @label;
                .outside-mixin();
                .child { display: block; }
            }
        }
        """
        guard let parsed = UserStyleSupport.parsed(from: less) else {
            return fail("Less style should parse")
        }
        if !parsed.isCompiled { fputs("valid Less error: \(parsed.compilationError ?? "nil")\n", stderr) }
        expect(parsed.isCompiled, "valid Less should compile")
        expect(!parsed.serializedConditions.contains("global"), "Less declarations outside a scope must not be global")
        guard let matchingCSS = UserStyleSupport.effectiveCSS(forContent: less, url: "https://example.com/page") else {
            return fail("matching Less section should produce CSS")
        }
        expect(matchingCSS.contains("color: #e91e63"), "Less variable default should render")
        if !matchingCSS.contains("wBlock") { fputs("LESS CSS: \(matchingCSS)\n", stderr); fail("Less text variable should render") }
        expect(matchingCSS.contains("border: 1px solid blue"), "Less mixin should render")
        expect(matchingCSS.contains(".card .child"), "Less nesting should render")
        expect(
            UserStyleSupport.effectiveCSS(forContent: less, url: "https://unrelated.invalid/") == nil,
            "scoped Less must not apply to unrelated URLs"
        )

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<String, Error>!
        DispatchQueue.global().async {
            result = Result { try UserStyleCompiler.compile(
                "@import url(\"https://example.com/theme.css\"); body { color: red; }",
                variables: []
            ) }
            semaphore.signal()
        }
        semaphore.wait()
        let importedCSS: String
        switch result {
        case .success(let css): importedCSS = css
        case .failure(let error): return fail("CSS @import should compile without asynchronous resolution: \(error)")
        case .none: return fail("Less compilation did not return")
        }
        expect(importedCSS.contains("@import url(\"https://example.com/theme.css\")"),
               "ordinary CSS @import must remain in compiled output")

        let malformed = """
        /* ==UserStyle==
        @name Broken Less
        @preprocessor less
        ==/UserStyle== */
        body { color: red;
        """
        guard let broken = UserStyleSupport.parsed(from: malformed) else {
            return fail("Malformed Less should preserve userstyle classification")
        }
        expect(UserStyleSupport.isUserStyleContent(malformed), "malformed Less remains a userstyle")
        expect(!broken.isCompiled, "malformed Less should fail compilation")
        let malformedRequest = UserStyleSupport.compilationRequest(
            for: malformed, preprocessor: "less", variables: [])
        expect(!malformedRequest.source.contains("==UserStyle=="), "compiler source must mask metadata")
        expect(
            malformedRequest.source.filter { $0 == "\n" }.count == malformed.filter { $0 == "\n" }.count,
            "metadata masking must preserve editor lines"
        )
        expect(
            (broken.compilationError ?? "").contains("line 6"),
            "Less error should use editor EOF line 6: \(broken.compilationError ?? "missing diagnostic")"
        )
        expect(UserStyleSupport.effectiveCSS(forContent: malformed, url: "https://example.com/") == nil, "failed Less must not inject CSS")

        let malformedSCSSWithVariable = """
        /* ==UserStyle==
        @name Broken SCSS variable
        @preprocessor scss
        @var color accent "Accent" red
        ==/UserStyle== */
        .card { color: #; }
        """
        let variableDiagnostic = UserStyleSupport.parsed(from: malformedSCSSWithVariable)?.compilationError ?? ""
        expect(variableDiagnostic.contains("line 6"),
               "Sass variable prelude must not shift editor diagnostics: \(variableDiagnostic)")
        expect(!variableDiagnostic.contains("7 │"),
               "Sass diagnostics must not retain a contradictory generated-source location")

        let malformedSCSSAfterPrefix = """
        .before { color: red; }
        /* ==UserStyle==
        @name Broken SCSS after prefix
        @preprocessor scss
        ==/UserStyle== */
        .after { color: #; }
        """
        let prefixDiagnostic = UserStyleSupport.parsed(from: malformedSCSSAfterPrefix)?.compilationError ?? ""
        expect(prefixDiagnostic.contains("line 6"),
               "non-leading metadata must not shift later diagnostics: \(prefixDiagnostic)")

        let malformedScopedSCSS = """
        /* ==UserStyle==
        @name Broken SCSS document
        @preprocessor scss
        ==/UserStyle== */
        @-moz-document domain("example.com"),
          url-prefix("https://app.example.net/") {
          .card { color: #; }
        }
        """
        let scopedDiagnostic = UserStyleSupport.parsed(from: malformedScopedSCSS)?.compilationError ?? ""
        expect(scopedDiagnostic.contains("line 7"),
               "multiline document rewriting must preserve editor diagnostics: \(scopedDiagnostic)")

        let sass = """
        /* ==UserStyle==
        @name Sass
        @preprocessor sass
        @var color accent "Accent" red
        ==/UserStyle== */
        .card
          color: $accent
          .child
            display: block
        """
        guard let sassParsed = UserStyleSupport.parsed(from: sass) else { return fail("Sass metadata should parse") }
        expect(sassParsed.isPreprocessorSupported && sassParsed.isCompiled, "Sass should compile")
        let sassCSS = UserStyleSupport.effectiveCSS(forContent: sass, url: "https://example.com/") ?? ""
        expect(sassCSS.contains(".card .child") && sassCSS.contains("color: red"), "Sass variables and nesting should render")

        let scss = """
        /* ==UserStyle==
        @name SCSS
        @preprocessor scss
        ==/UserStyle== */
        .card { .child { color: blue; } }
        """
        guard let scssParsed = UserStyleSupport.parsed(from: scss) else { return fail("SCSS metadata should parse") }
        expect(scssParsed.isCompiled, "SCSS should compile")
        expect((UserStyleSupport.effectiveCSS(forContent: scss, url: "https://example.com/") ?? "").contains(".card .child"), "SCSS nesting should render")

        let scopedSCSS = """
        /* ==UserStyle==
        @name Scoped SCSS
        @preprocessor scss
        ==/UserStyle== */
        @media all { .global { color: black; } }
        @-moz-document domain("example.com"),
          url-prefix("https://app.example.net/") {
            .scoped { .child { color: red; } }
        }
        @-moz-document domain("other.example") {
            .other { color: blue; }
        }
        """
        guard let scopedParsed = UserStyleSupport.parsed(from: scopedSCSS) else {
            return fail("Scoped SCSS metadata should parse")
        }
        expect(scopedParsed.isCompiled, "multiline scoped SCSS should compile")
        let compiledScoped = scopedParsed.compiledArtifact?.body ?? ""
        expect(compiledScoped.contains("@media all"), "ordinary media rules must remain unchanged")
        expect(compiledScoped.contains("@-moz-document domain(\"example.com\"),"),
               "multiline document conditions must be restored")
        expect(!compiledScoped.contains("__wblock_document_"), "Sass markers must not escape compilation")
        expect(!compiledScoped.contains("{ {"), "restored document rules must contain one opening brace")
        let matchingScoped = UserStyleSupport.effectiveCSS(
            forContent: scopedSCSS, url: "https://example.com/page"
        ) ?? ""
        expect(matchingScoped.contains(".global") && matchingScoped.contains(".scoped .child"),
               "matching SCSS should include global and selected scoped CSS")
        expect(!matchingScoped.contains(".other"), "nonmatching SCSS sections must stay excluded")
        let unrelatedScoped = UserStyleSupport.effectiveCSS(
            forContent: scopedSCSS, url: "https://unrelated.invalid/"
        ) ?? ""
        expect(unrelatedScoped.contains(".global"), "ordinary media CSS should remain global")
        expect(!unrelatedScoped.contains(".scoped") && !unrelatedScoped.contains(".other"),
               "scoped SCSS must not leak to unrelated URLs")

        let scopedSass = """
        /* ==UserStyle==
        @name Scoped Sass
        @preprocessor sass
        ==/UserStyle== */
        @-moz-document domain("example.com"),
          url-prefix("https://app.example.net/")
          .sass-scope
            color: red
        """
        guard let scopedSassParsed = UserStyleSupport.parsed(from: scopedSass) else {
            return fail("Scoped Sass metadata should parse")
        }
        expect(scopedSassParsed.isCompiled,
               "multiline scoped Sass should compile: \(scopedSassParsed.compilationError ?? "missing diagnostic")")
        let matchingSass = UserStyleSupport.effectiveCSS(
            forContent: scopedSass, url: "https://example.com/page"
        ) ?? ""
        expect(matchingSass.contains(".sass-scope"),
               "matching multiline Sass condition should inject")
        expect(UserStyleSupport.effectiveCSS(
            forContent: scopedSass, url: "https://unrelated.invalid/"
        ) == nil, "multiline Sass condition must not leak")

        let rejectedSassImport = """
        /* ==UserStyle==
        @name Sass import
        @preprocessor scss
        ==/UserStyle== */
        @use "remote";
        """
        expect(UserStyleSupport.parsed(from: rejectedSassImport)?.isCompiled == false,
               "Sass module imports must be rejected offline")

        let stylus = """
        /* ==UserStyle==
        @name Stylus
        @preprocessor stylus
        ==/UserStyle== */
        .card
          color: red
          .child
            display: block
        """
        guard let stylusParsed = UserStyleSupport.parsed(from: stylus) else { return fail("Stylus metadata should parse") }
        expect(stylusParsed.isPreprocessorSupported && stylusParsed.isCompiled, "Stylus should compile")
        expect((UserStyleSupport.effectiveCSS(forContent: stylus, url: "https://example.com/") ?? "").contains(".card .child"), "Stylus nesting should render")

        let rejectedStylusImport = """
        /* ==UserStyle==
        @name Stylus import
        @preprocessor stylus
        ==/UserStyle== */
        @import 'remote'
        """
        expect(UserStyleSupport.parsed(from: rejectedStylusImport)?.isCompiled == false,
               "Stylus imports must be rejected offline")

        let postcss = """
        /* ==UserStyle==
        @name PostCSS
        @preprocessor postcss
        @var color accent "Accent" red
        ==/UserStyle== */
        .card { .child { color: blue; } }
        """
        guard let postcssParsed = UserStyleSupport.parsed(from: postcss) else { return fail("PostCSS metadata should parse") }
        expect(postcssParsed.isCompiled, "PostCSS should compile")
        let postcssCSS = UserStyleSupport.effectiveCSS(forContent: postcss, url: "https://example.com/") ?? ""
        expect(postcssCSS.hasPrefix(":root {"), "PostCSS should receive CSS variable prelude after compilation")
        expect(postcssCSS.contains(".card .child"), "PostCSS nesting should render")

        let malformedPostCSS = """
        /* ==UserStyle==
        @name Broken PostCSS
        @preprocessor postcss
        ==/UserStyle== */
        .broken { color: red;
        """
        expect(UserStyleSupport.parsed(from: malformedPostCSS)?.isCompiled == false,
               "malformed PostCSS must fail compilation")

        let revisions = [
            "less": UserStylePreprocessorService.lessRevision,
            "sass": UserStylePreprocessorService.sassRevision,
            "scss": UserStylePreprocessorService.sassRevision,
            "stylus": UserStylePreprocessorService.stylusRevision,
            "postcss": UserStylePreprocessorService.postCSSRevision
        ]
        for (preprocessor, revision) in revisions {
            expect(UserStylePreprocessorService.backend(for: preprocessor) != nil,
                   "\(preprocessor) backend must be registered")
            expect(UserStylePreprocessorService.compilerRevision(for: preprocessor) == revision,
                   "\(preprocessor) revision must identify its pinned artifact")
        }

        let oversized = String(repeating: "a", count: UserStyleCompiler.maximumSourceBytes + 1)
        do {
            _ = try UserStyleCompiler.compile(oversized, variables: [])
            fail("oversized Less source should be rejected")
        } catch let error as UserStyleCompiler.CompilationError {
            expect(error.message.contains("2 MiB"), "oversized source should report its bound")
        } catch {
            fail("oversized Less source returned the wrong error")
        }
    }

    static func testCompiledStyleCacheAndArtifactIdentity() {
        let source = """
        /* ==UserStyle==
        @name Cache Probe
        @preprocessor less
        ==/UserStyle== */
        body { color: red; }
        """
        let changed = source.replacingOccurrences(of: "red", with: "blue")
        let id = UUID()
        var installed = UserScript(id: id, name: "Cache Probe", content: source)
        installed.replaceContentAndParseMetadata(source, compiledBody: "installed-css")
        var candidate = installed
        candidate.replaceContentAndParseMetadata(changed, compiledBody: "candidate-css")
        expect(installed.compiledStyleBody == "installed-css", "same UUID must not share a changed transient body")
        expect(candidate.compiledStyleBody == "candidate-css", "candidate body must use its source identity")
        expect(installed.content == source, "authoritative source must remain unchanged")

        expect(UserStyleSupport.effectiveCSS(forContent: source, compiledBody: "body { color: red; }", url: "https://example.com")?.contains("color: red") == true,
               "precompiled effective CSS should work without a compiler fallback")
        expect(UserStyleSupport.effectiveCSS(forContent: source, compiledBody: nil, url: "https://example.com") == nil,
               "runtime must fail closed without compiler-backed output")

        let request = UserStyleSupport.compilationRequest(
            for: source, preprocessor: "less", variables: [])
        let artifact = UserStyleCompiledArtifact(request: request, compilerRevision: UserStylePreprocessorService.lessRevision, body: "body { color: red; }")
        expect(UserStylePreprocessorService.validate(artifact, for: request), "exact artifact identity should validate")
        expect(
            request.source.filter { $0 == "\n" }.count == source.filter { $0 == "\n" }.count,
            "sidecar request must preserve editor line mapping"
        )
        let changedSource = UserStyleSupport.compilationRequest(
            for: changed, preprocessor: "less", variables: [])
        expect(!UserStylePreprocessorService.validate(artifact, for: changedSource), "changed source must reject the artifact")
        let changedOptions = UserStyleCompilationRequest(source: request.source, preprocessor: "less", variables: [], options: ["compress": "true"], sourceDigest: request.sourceDigest)
        expect(!UserStylePreprocessorService.validate(artifact, for: changedOptions), "changed options must reject the artifact")
        let changedRevision = UserStyleCompiledArtifact(request: request, compilerRevision: "other-revision", body: artifact.body)
        expect(!UserStylePreprocessorService.validate(changedRevision, for: request), "changed revision must reject the artifact")
        var tamperedJSON = try! JSONSerialization.jsonObject(
            with: JSONEncoder().encode(artifact)
        ) as! [String: Any]
        tamperedJSON["body"] = "body { color: blue; }"
        let changedBody = try! JSONDecoder().decode(
            UserStyleCompiledArtifact.self,
            from: JSONSerialization.data(withJSONObject: tamperedJSON)
        )
        expect(!UserStylePreprocessorService.validate(changedBody, for: request), "changed body digest must reject the artifact")
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

        // Userscripts-app convention: @match in the metadata block scopes global CSS (#599).
        var matchScoped = UserScript(
            name: "m",
            content: """
            /* ==UserStyle==
            @name        DuckDuckGo CSS Style
            @match       *://*.duckduckgo.com/*
            @exclude-match *://*.duckduckgo.com/settings*
            ==/UserStyle== */
            div.js-notification-text { visibility: hidden; }
            """
        )
        matchScoped.parseMetadata()
        expect(matchScoped.isUserStyle, "@match style should be detected")
        expect(matchScoped.matches(url: "https://duckduckgo.com/?q=x"), "@match style should match its host")
        expect(matchScoped.matches(url: "https://html.duckduckgo.com/html"), "@match wildcard subdomain should match")
        expect(!matchScoped.matches(url: "https://duckduckgo.com/settings?x"), "@exclude-match should exclude")
        expect(!matchScoped.matches(url: "https://example.com/"), "@match style must not apply elsewhere")
        expect(!matchScoped.matches.contains("global"), "@match style must not be serialized as global")
        expect(
            UserStyleSupport.effectiveCSS(forContent: matchScoped.content, url: "https://duckduckgo.com/") != nil,
            "@match style should produce CSS on a matching page"
        )
        expect(
            UserStyleSupport.effectiveCSS(forContent: matchScoped.content, url: "https://example.com/") == nil,
            "@match style must produce no CSS elsewhere"
        )

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
        expect(UserStyleSupport.isUserStylePath("/styles/theme.less"), ".less paths should be recognized as userstyles")
        expect(UserStyleSupport.isUserStyleURL(URL(string: "https://example.com/raw?filename=theme.less")!), ".less query URLs should be recognized as userstyles")
        expect(
            UserScriptURLSupport.validatedRemoteURL(from: "https://example.com/styles/theme.less") != nil,
            ".less path remote URLs should validate"
        )
        expect(
            UserScriptURLSupport.validatedRemoteURL(from: "https://example.com/raw?filename=theme.less") != nil,
            ".less query-value remote URLs should validate"
        )
        expect(
            UserScriptURLSupport.validatedRemoteURL(from: "https://example.com/styles/dark.scss") != nil,
            ".scss remote URLs should validate"
        )

        let compilerExtensions = [
            "less": "less",
            "sass": "sass",
            "scss": "scss",
            "styl": "stylus",
            "pcss": "postcss"
        ]
        for (fileExtension, preprocessor) in compilerExtensions {
            let pathURL = URL(string: "https://example.com/styles/theme.\(fileExtension)")!
            let queryURL = URL(string: "https://example.com/raw?filename=theme.\(fileExtension)")!
            expect(UserScriptURLSupport.validatedRemoteURL(from: pathURL.absoluteString) != nil,
                   ".\(fileExtension) path URLs should validate")
            expect(UserScriptURLSupport.validatedRemoteURL(from: queryURL.absoluteString) != nil,
                   ".\(fileExtension) query URLs should validate")
            expect(UserStyleSupport.isUserStyleURL(queryURL),
                   ".\(fileExtension) query URLs should be userstyles")
            expectEqual(UserStyleSupport.expectedPreprocessor(for: pathURL), preprocessor,
                        ".\(fileExtension) should require \(preprocessor)")
            expectEqual(UserStyleSupport.expectedPreprocessor(for: queryURL), preprocessor,
                        "query .\(fileExtension) should require \(preprocessor)")
            expectEqual(UserScriptURLSupport.displayName(forFilename: "theme.\(fileExtension)"),
                        "theme", ".\(fileExtension) display names should strip the extension")
        }
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
        expectEqual(UserScriptURLSupport.displayName(forFilename: "theme.less"), "theme", "display name should strip .less")
        expectEqual(
            UserScriptURLSupport.displayName(forRemoteURL: URL(string: "https://example.com/raw?filename=theme.less")!),
            "theme",
            "display name should strip query-value .less"
        )
    }

    static func testRemoteImportInlining() {
        // Detection: only Less userstyles with unambiguous remote imports qualify.
        let style = """
        /* ==UserStyle==
        @name Remote import
        @preprocessor less
        ==/UserStyle== */
        @import (less) "https://example.com/lib/palette.less";
        @-moz-document domain("example.com") {
            body { color: @accent-from-lib; .lib-border(); }
        }
        """
        expect(
            UserStyleRemoteImportInliner.containsRemoteLessImports(in: style),
            "remote (less) import in a Less userstyle should be detected"
        )
        expect(
            UserStyleRemoteImportInliner.containsRemoteLessImports(
                in: style.replacingOccurrences(of: "@preprocessor less", with: "@preprocessor Less")
            ),
            "capitalized @preprocessor Less must pass the normalized gate"
        )
        expect(
            !UserStyleRemoteImportInliner.containsRemoteLessImports(
                in: style.replacingOccurrences(of: "@preprocessor less", with: "@preprocessor uso")
            ),
            "non-Less userstyles must never inline"
        )

        let statements = UserStyleRemoteImportInliner.inlineableImports(in: style)
        expectEqual(statements.count, 1, "exactly one inlineable import should be found")
        expectEqual(
            statements.first?.url ?? "",
            "https://example.com/lib/palette.less",
            "the import URL should be extracted"
        )

        // Disqualified statements are preserved untouched.
        let skipped = """
        @import "local/thing.less";
        @import "https://example.com/screen.less" print;
        @import (css) "https://example.com/forced-css.less";
        @import "https://example.com/plain.css";
        @import (reference) "https://example.com/ref.less";
        /* @import (less) "https://example.com/comment.less"; */
        // @import (less) "https://example.com/line-comment.less";
        .rule { content: "@import (less) 'https://example.com/string.less';"; }
        """
        expect(
            UserStyleRemoteImportInliner.inlineableImports(in: skipped).isEmpty,
            "relative, media-query, css/reference-option, plain-css, commented, and quoted imports must be skipped"
        )
        expect(
            !UserStyleRemoteImportInliner.inlineableImports(
                in: "@import url( 'https://example.com/via-url.less' );"
            ).isEmpty,
            "url(...) form with a .less target should qualify"
        )

        let finished = DispatchSemaphore(value: 0)
        var checksPassed = false
        Task {
            defer { finished.signal() }

            // End-to-end regression for issue #578: the imported library defines
            // symbols the style body references, so the compile only succeeds if
            // inlining ran before compilation.
            let library = "@accent-from-lib: #abcdef;\n.lib-border() { border-width: 2px; }\n"
            var fetchCount = 0
            let inlined: String
            do {
                inlined = try await UserStyleRemoteImportInliner.inliningRemoteImports(in: style) { url in
                    fetchCount += 1
                    expectEqual(url.absoluteString, "https://example.com/lib/palette.less", "fetch should receive the import URL")
                    return library
                }
            } catch {
                return fail("inlining should succeed: \(error)")
            }
            expectEqual(fetchCount, 1, "the import should be fetched exactly once")
            expect(UserStyleRemoteImportInliner.inlineableImports(in: inlined).isEmpty, "no inlineable imports may remain after inlining")
            expect(inlined.contains("@accent-from-lib: #abcdef;"), "the fetched library source should be spliced in")
            guard let parsed = UserStyleSupport.parsed(from: inlined) else {
                return fail("inlined style should parse")
            }
            if !parsed.isCompiled { fputs("inlined compile error: \(parsed.compilationError ?? "nil")\n", stderr) }
            expect(parsed.isCompiled, "inlined style should compile offline")
            let css = UserStyleSupport.effectiveCSS(forContent: inlined, url: "https://example.com/page")
            expect(css?.contains("#abcdef") == true, "library variable should resolve in compiled CSS")
            expect(css?.contains("border-width: 2px") == true, "library mixin should resolve in compiled CSS")

            // Nested imports resolve recursively; repeated imports follow
            // import-once semantics and are fetched a single time.
            let nested = """
            /* ==UserStyle==
            @name Nested
            @preprocessor less
            ==/UserStyle== */
            @import (less) "https://example.com/a.less";
            @import (less) "https://example.com/a.less";
            """
            var fetches: [String] = []
            let nestedResult = try? await UserStyleRemoteImportInliner.inliningRemoteImports(in: nested) { url in
                fetches.append(url.absoluteString)
                if url.absoluteString.hasSuffix("a.less") {
                    return "@import (less) \"https://example.com/b.less\";\n.from-a() {}"
                }
                return ".from-b() {}"
            }
            expectEqual(fetches, ["https://example.com/a.less", "https://example.com/b.less"], "nested imports should fetch depth-first, once per URL")
            expect(nestedResult?.contains(".from-a") == true && nestedResult?.contains(".from-b") == true, "nested sources should both be inlined")

            // Chains deeper than the maximum depth are rejected.
            var depthError: Error?
            do {
                var counter = 0
                _ = try await UserStyleRemoteImportInliner.inliningRemoteImports(in: nested) { _ in
                    counter += 1
                    return "@import (less) \"https://example.com/deep-\(counter).less\";"
                }
            } catch { depthError = error }
            expect(depthError is UserStyleRemoteImportInliner.InlineError, "over-deep import chains should throw InlineError")

            // Fetch failures surface as a download error naming the URL.
            struct StubError: Error {}
            var fetchError: Error?
            do {
                _ = try await UserStyleRemoteImportInliner.inliningRemoteImports(in: style) { _ in throw StubError() }
            } catch { fetchError = error }
            expect(
                (fetchError as? UserStyleRemoteImportInliner.InlineError)?.message.contains("palette.less") == true,
                "fetch failure should name the import URL"
            )

            // Non-Less content passes through byte-identical without fetching.
            let plainCSS = "/* ==UserStyle==\n@name Plain\n==/UserStyle== */\n@import \"https://example.com/x.less\";\nbody { color: red; }"
            let untouched = try? await UserStyleRemoteImportInliner.inliningRemoteImports(in: plainCSS) { _ in
                fail("plain CSS must not trigger fetches"); return ""
            }
            expectEqual(untouched ?? "", plainCSS, "plain CSS userstyles must pass through unchanged")

            checksPassed = true
        }
        finished.wait()
        expect(checksPassed, "remote import inlining checks should complete")
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
