import Foundation
import wBlockCoreService

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

let cases: [(preprocessor: String, body: String, expected: String)] = [
    ("less", "@accent: red; .a { color: @accent; .b { display: block; } }", ".a .b"),
    ("scss", "$accent: red; .a { color: $accent; .b { display: block; } }", ".a .b"),
    ("sass", "$accent: red\n.a\n  color: $accent\n  .b\n    display: block", ".a .b"),
    ("stylus", "accent = red\n.a\n  color accent\n  .b\n    display block", ".a .b"),
    ("postcss", ".a { color: red; .b { display: block; } }", ".a .b")
]

for testCase in cases {
    let source = """
    /* ==UserStyle==
    @name \(testCase.preprocessor)
    @preprocessor \(testCase.preprocessor)
    ==/UserStyle== */
    \(testCase.body)
    """
    guard let parsed = UserStyleSupport.parsed(from: source) else {
        fail("\(testCase.preprocessor) metadata did not parse")
    }
    expect(parsed.isCompiled,
           "\(testCase.preprocessor) failed: \(parsed.compilationError ?? "unknown")")
    let css = UserStyleSupport.effectiveCSS(
        forContent: source,
        url: "https://example.com/"
    ) ?? ""
    expect(css.contains(testCase.expected),
           "\(testCase.preprocessor) output was \(css)")
}

let scopedSCSS = """
/* ==UserStyle==
@name scoped
@preprocessor scss
==/UserStyle== */
@media all { .global { color: black; } }
@-moz-document domain("example.com"),
  url-prefix("https://app.example.net/") {
    .scoped { .child { color: red; } }
}
"""
let matching = UserStyleSupport.effectiveCSS(
    forContent: scopedSCSS,
    url: "https://example.com/page"
) ?? ""
let unrelated = UserStyleSupport.effectiveCSS(
    forContent: scopedSCSS,
    url: "https://unrelated.invalid/"
) ?? ""
expect(matching.contains(".global") && matching.contains(".scoped .child"),
       "SCSS document scope did not match")
expect(unrelated.contains(".global") && !unrelated.contains(".scoped"),
       "SCSS document scope leaked")

func withTemporaryFile(
    extension fileExtension: String,
    content: String,
    _ body: (URL) throws -> Void
) rethrows {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(fileExtension)
    try! content.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(url)
}

let executableScript = """
// ==UserScript==
// @name Wrong classification
// ==/UserScript==
alert('must not import');
"""
for fileExtension in ["css", "scss"] {
    try withTemporaryFile(extension: fileExtension, content: executableScript) { url in
        do {
            _ = try UserScriptManager.stageUserScriptImport(fromLocalFile: url)
            fail(".\(fileExtension) executable content was accepted")
        } catch UserScriptImportError.missingMetadata {
            // Expected.
        }
    }
}

let mismatch = """
/* ==UserStyle==
@name Wrong compiler
@preprocessor less
==/UserStyle== */
body { color: red; }
"""
try withTemporaryFile(extension: "scss", content: mismatch) { url in
    do {
        _ = try UserScriptManager.stageUserScriptImport(fromLocalFile: url)
        fail("mismatched .scss metadata was accepted")
    } catch UserScriptImportError.stylePreprocessorMismatch(let expected, let declared) {
        expect(expected == "scss" && declared == "less", "wrong mismatch details")
    }
}

print("PASS: packaged userstyle compilers")
