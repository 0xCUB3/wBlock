//
// scripts/test_adguard_syntax_highlighter.swift
//
// Regression coverage for wBlock's `AdGuardSyntaxHighlighter` tokenizer, using
// the edge-case rule fixtures from AdGuardTeam/RulesEditor's
// `test/simpleTokenize.test.ts` (mapped onto wBlock's token vocabulary).
//
// Run via:
//   swiftc -parse-as-library \
//     wBlock/AdGuardSyntaxHighlighter.swift \
//     scripts/test_adguard_syntax_highlighter.swift \
//     -o /tmp/syntaxtest && /tmp/syntaxtest
//
// Prints `PASS` on success, `FAIL: <message>` (exit 1) on the first divergence.
//
// Vocabulary mapping note
// -----------------------
// wBlock's `AdGuardSyntaxHighlighter` produces *semantic* token categories
// (comment / elementHiding / urlBlocking / exception / modifier / extendedCSS /
// scriptlet / htmlFiltering / regexPattern / sectionHeader / plain) rather than
// CodeMirror token names (keyword / operator / string / def / string-2 / null /
// comment). AdGuard's chunks also split finely (e.g. it strips the leading `@@`
// and trailing `^` into separate `keyword` tokens, and divides
// `$domain=a.com|b.com` into per-domain `string` tokens joined by `,`/`=`
// operators). wBlock's regex model intentionally keeps the URL body, exception
// prefix, and modifier list as coarse single segments and does not separate the
// trailing `^` separator.
//
// Each fixture's expected output below is therefore asserted in wBlock's own
// vocabulary: the substring boundaries are taken from AdGuard's fixtures where
// the two vocabularies agree (markers, modifier lists, regex delimiters) and
// re-expressed as wBlock tokens otherwise. The intent is to pin wBlock's
// documented behaviour against these tricky inputs so future refactors cannot
// drift silently — *not* to reproduce AdGuard's per-token boundaries exactly.

import Foundation

@main
struct AdGuardSyntaxHighlighterTests {
    static func main() {
        let highlighter = AdGuardSyntaxHighlighter()

        // MARK: Network rules

        // @@|https://example.org/unified/someJsFile.js$domain=domain.one.com|domaintwo.com|domainthree.com
        // AdGuard:     `@@|` keyword / body null / `$domain` keyword / `=` operator / domains string.
        // wBlock view: `@@` exception (the single leading `|` is *not* a `||` host anchor and stays
        //               part of the URL plain body), then plain body, then the full trailing
        //               `$domain=...` block colored as a single modifier token.
        expect(
            highlighter.tokenize("@@|https://example.org/unified/someJsFile.js$domain=domain.one.com|domaintwo.com|domainthree.com"),
            [
                (.exception, "@@"),
                (.plain, "|https://example.org/unified/someJsFile.js"),
                (.modifier, "$domain=domain.one.com|domaintwo.com|domainthree.com"),
            ],
            "single-pipe allowlist exception with $domain= list"
        )

        // ||example.com/assets/Cookie.$stylesheet,script
        expect(
            highlighter.tokenize("||example.com/assets/Cookie.$stylesheet,script"),
            [
                (.urlBlocking, "||"),
                (.plain, "example.com/assets/Cookie."),
                (.modifier, "$stylesheet,script"),
            ],
            "URL block with $modifier list lacking trailing separator"
        )

        // @@||example.no/static/*/frontend/folder/path/$domain=example.no
        expect(
            highlighter.tokenize("@@||example.no/static/*/frontend/folder/path/$domain=example.no"),
            [
                (.exception, "@@"),
                (.plain, "||example.no/static/*/frontend/folder/path/"),
                (.modifier, "$domain=example.no"),
            ],
            "exception prefixed host anchor with $domain= modifier"
        )

        // @@||example.org^
        // AdGuard strips the trailing `^` into its own keyword token; wBlock keeps
        // the URL body (including `^`) as one plain segment after the exception marker.
        expect(
            highlighter.tokenize("@@||example.org^"),
            [
                (.exception, "@@"),
                (.plain, "||example.org^"),
            ],
            "bare exception with raw URL body"
        )

        // MARK: Element-hiding rules

        // example.com.it#@##some-sdk
        // AdGuard:   domains string / `#@#` keyword / selector def.
        // wBlock:    plain domains, `#@#` elementHiding marker, then a plain selector
        //            (the trailing `#some-sdk` has no second adjacent `#`, so the inline
        //            `#/##` alternation does not over-match the body).
        expect(
            highlighter.tokenize("example.com.it#@##some-sdk"),
            [
                (.plain, "example.com.it"),
                (.elementHiding, "#@#"),
                (.plain, "#some-sdk"),
            ],
            "exception element-hiding marker with selector starting with #"
        )

        // example.com#@#.cookie-confirm
        expect(
            highlighter.tokenize("example.com#@#.cookie-confirm"),
            [
                (.plain, "example.com"),
                (.elementHiding, "#@#"),
                (.plain, ".cookie-confirm"),
            ],
            "exception element-hiding marker with class selector"
        )

        // MARK: Regex rules

        // /example.org/
        // AdGuard splits into `/` keyword / `example.org` string-2 / `/` keyword.
        // wBlock colors the entire `/example.org/` (delimiters included) as regexPattern.
        expect(
            highlighter.tokenize("/example.org/"),
            [
                (.regexPattern, "/example.org/"),
            ],
            "single-line regex rule"
        )

        // MARK: Comments — `!` family (already correct pre-refactor)

        expectEqual(highlighter.tokenize("!comment"),       [(.comment, "!comment")],       "bang comment, no space")
        expectEqual(highlighter.tokenize("!"),               [(.comment, "!")],               "bare bang")
        expectEqual(highlighter.tokenize("!!"),              [(.comment, "!!")],              "double bang")
        expectEqual(highlighter.tokenize("! comment"),       [(.comment, "! comment")],       "bang comment with space")
        expectEqual(highlighter.tokenize("!#comment"),       [(.comment, "!#comment")],       "bang-hash comment")
        expectEqual(highlighter.tokenize("!+comment"),       [(.comment, "!+comment")],       "bang-plus comment")
        expectEqual(
            highlighter.tokenize("! #########################"),
            [(.comment, "! #########################")],
            "bang comment followed by hash wall"
        )

        // MARK: Comments — `#` family (the bug this test pins down)
        //
        // wBlock previously did NOT treat single-`#` lines as comments, leaving them
        // as plain or (for `##…` sequences) mis-coloring them as elementHiding.
        // AdGuard's `RuleFactory.isComment` treats a leading `#` as a comment unless
        // it is followed immediately by a cosmetic marker character
        // (`#`, `@`, `?`, `%`, `$`). The Behat-style fixtures below cover the
        // accepted shapes: lone `#`, `# comment`, `#comment`, `#+comment`, and a
        // `# `-prefixed wall-of-hashes (note that `####…` *without* a leading
        // space is a cosmetic ElementHiding per AdGuard and is NOT a comment).
        expectEqual(highlighter.tokenize("#"),               [(.comment, "#")],               "lone hash")
        expectEqual(highlighter.tokenize("# #"),             [(.comment, "# #")],             "hash space hash")
        expectEqual(highlighter.tokenize("#comment"),        [(.comment, "#comment")],        "hash comment without space")
        expectEqual(highlighter.tokenize("# comment"),       [(.comment, "# comment")],       "hash comment with space")
        expectEqual(highlighter.tokenize("#+comment"),       [(.comment, "#+comment")],       "hash-plus comment")
        expectEqual(
            highlighter.tokenize("# ########################"),
            [(.comment, "# ########################")],
            "hash-prefixed wall of hashes is a comment"
        )

        // MARK: Cosmetic markers must NOT be swallowed by the comment rule

        // `##` is a (degenerate) ElementHiding marker, not a comment.
        expectEqual(
            highlighter.tokenize("##"),
            [(.elementHiding, "##")],
            "bare double-hash is ElementHiding marker, not a comment"
        )
        // `#%#body` scriptlet — the `#%#` lookahead guard must let the scriptlet
        // full-line pattern win instead of the comment pattern.
        expectEqual(
            highlighter.tokenize("example.com#%#//scriptlet('foo')"),
            [(.scriptlet, "example.com#%#//scriptlet('foo')")],
            "scriptlet rule is not treated as a comment"
        )
        // `#$#body` is a CSS cosmetic rule with a `#$#` elementHiding marker.
        expectEqual(
            highlighter.tokenize("example.com#$#body { background: #333; }"),
            [
                (.plain, "example.com"),
                (.elementHiding, "#$#"),
                (.plain, "body { background: #333; }"),
            ],
            "CSS cosmetic rule (#$#) marker is elementHiding, not a comment"
        )

        // MARK: Modifier edge cases from the fixture set

        // Negated modifier list: `$~script,~image` — AdGuard would per-split
        // modifiers with `,` operators; wBlock colors the full trailing `$…`
        // block as one modifier token.
        expect(
            highlighter.tokenize("||example.org^$~script,~image"),
            [
                (.urlBlocking, "||"),
                (.plain, "example.org^"),
                (.modifier, "$~script,~image"),
            ],
            "negated modifier list"
        )
        // `$important` standalone modifier.
        expect(
            highlighter.tokenize("||example.org^$important"),
            [
                (.urlBlocking, "||"),
                (.plain, "example.org^"),
                (.modifier, "$important"),
            ],
            "important modifier"
        )

        // MARK: Invalid / unparseable inputs
        //
        // AdGuard's simpleTokenizer returns a single plain `null` token for these;
        // wBlock's regex model is more permissive and matches lying-around cosmetic
        // markers. The pinning below reflects wBlock's *actual* current behaviour so
        // the test stays a real regression baseline rather than a tautology: changes
        // to the highlighter that alter these outputs will surface here.
        expectEqual(
            highlighter.tokenize(" !"),
            [(.plain, " !")],
            "leading-space bang is plain (no full-line comment match)"
        )
        expectEqual(
            highlighter.tokenize("#########################"),
            [(.elementHiding, "########################"), (.plain, "#")],
            "bare wall of hashes colors paired ## markers as elementHiding (wBlock divergence from AdGuard's null); trailing odd # stays plain"
        )
        expectEqual(
            highlighter.tokenize("$$$$$"),
            [(.htmlFiltering, "$$$$$")],
            "bare dollar run matches the $$ html-filtering pattern (wBlock divergence from AdGuard's null)"
        )

        print("PASS")
    }

    // MARK: - Helpers

    private static func expect(
        _ actual: [(token: AdGuardSyntaxHighlighter.TokenType, str: String)],
        _ expected: [(AdGuardSyntaxHighlighter.TokenType, String)],
        _ message: String
    ) {
        expectEqual(actual, expected, message)
    }

    private static func expectEqual(
        _ actual: [(token: AdGuardSyntaxHighlighter.TokenType, str: String)],
        _ expected: [(AdGuardSyntaxHighlighter.TokenType, String)],
        _ message: String
    ) {
        guard actual.count == expected.count else {
            fail("\(message)\n  expected \(expected.count) tokens: \(dump(expected))\n  got      \(actual.count) tokens: \(dump(actual))")
        }
        for (index, pair) in actual.enumerated() {
            let (eToken, eStr) = expected[index]
            if pair.token != eToken || pair.str != eStr {
                fail("\(message)\n  token \(index) expected \(eToken)/\(eStr.debugDescription)\n              got      \(pair.token)/\(pair.str.debugDescription)\n  full expected: \(dump(expected))\n  full actual:   \(dump(actual))")
            }
        }
    }

    private static func dump(_ tokens: [(AdGuardSyntaxHighlighter.TokenType, String)]) -> String {
        tokens.map { "\($0.0.rawValue)(`\($0.1)`)" }.joined(separator: ", ")
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}