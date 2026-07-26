//
// scripts/test_userscript_metadata_emoji_strip.swift
//
// Regression for issue #484: digits (and other ASCII text) in @name /
// @description must survive emoji stripping during parseMetadata().
//
// Run via:
//   swiftc -parse-as-library \
//     wBlockCoreService/UserScript.swift \
//     wBlockCoreService/UserStyle.swift \
//     scripts/test_userscript_metadata_emoji_strip.swift \
//     -o /tmp/userscript_emoji_strip && /tmp/userscript_emoji_strip
//

import Foundation

@main
struct UserScriptMetadataEmojiStripTests {
    static func main() {
        testDigitsPreservedInNameAndDescription()
        testEmojiGlyphsStillRemoved()
        testUserStyleDigitsPreserved()
        testASCIISymbolsPreserved()
        print("PASS: userscript metadata emoji strip")
    }

    private static func testDigitsPreservedInNameAndDescription() {
        var script = UserScript(
            name: "fallback",
            content: """
            // ==UserScript==
            // @name         Simple 123 Logger 1.0
            // @description  Logs "123" to the console on every page
            // @version      1.0
            // @match        *://*/*
            // ==/UserScript==

            console.log('123');
            """
        )
        script.parseMetadata()

        expectEqual(
            script.name,
            "Simple 123 Logger 1.0",
            "digits in @name must not be stripped (issue #484)"
        )
        expectEqual(
            script.description,
            "Logs \"123\" to the console on every page",
            "digits in @description must not be stripped (issue #484)"
        )
        expectEqual(script.version, "1.0", "version digits must still parse")
    }

    private static func testEmojiGlyphsStillRemoved() {
        var script = UserScript(
            name: "fallback",
            content: """
            // ==UserScript==
            // @name         🔥 Cool Script 2.0 🇺🇸
            // @description  Helps with ads ✨
            // @match        *://example.com/*
            // ==/UserScript==

            console.log(1);
            """
        )
        script.parseMetadata()

        expectEqual(
            script.name,
            "Cool Script 2.0",
            "emoji glyphs should still be stripped from @name while digits remain"
        )
        expectEqual(
            script.description,
            "Helps with ads",
            "emoji glyphs should still be stripped from @description"
        )
    }

    private static func testUserStyleDigitsPreserved() {
        var style = UserScript(
            name: "fallback",
            content: """
            /* ==UserStyle==
            @name           Dark Theme 2024
            @description    Makes example.com dark in 2024
            @version        2.1.0
            ==/UserStyle== */

            @-moz-document domain("example.com") {
                body { background: #111 !important; }
            }
            """
        )
        style.parseMetadata()

        expect(style.isUserStyle, "fixture should parse as a userstyle")
        expectEqual(
            style.name,
            "Dark Theme 2024",
            "digits in userstyle @name must not be stripped"
        )
        expectEqual(
            style.description,
            "Makes example.com dark in 2024",
            "digits in userstyle @description must not be stripped"
        )
    }

    private static func testASCIISymbolsPreserved() {
        var script = UserScript(
            name: "fallback",
            content: """
            // ==UserScript==
            // @name         Script #1 * v2
            // @description  Uses # and * freely
            // @match        *://example.com/*
            // ==/UserScript==

            console.log(1);
            """
        )
        script.parseMetadata()

        expectEqual(
            script.name,
            "Script #1 * v2",
            "ASCII # and * must not be treated as emoji"
        )
        expectEqual(
            script.description,
            "Uses # and * freely",
            "ASCII # and * must remain in @description"
        )
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
