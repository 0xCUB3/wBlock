import Foundation
import wBlockCoreService

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

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

let finished = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    let cases: [(preprocessor: String, body: String, expected: String)] = [
        ("less", "@accent: red; .a { color: @accent; .b { display: block; } }", ".a .b"),
        ("stylus", "accent = red\n.a\n  color accent\n  .b\n    filter invert(65%) saturate(277%)\n    color tint(#000, 50%)", "#7f7f7f")
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

    let executableScript = """
    // ==UserScript==
    // @name Wrong classification
    // ==/UserScript==
    alert('must not import');
    """
    for fileExtension in ["css", "styl"] {
        try! withTemporaryFile(extension: fileExtension, content: executableScript) { url in
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
    try! withTemporaryFile(extension: "styl", content: mismatch) { url in
        do {
            _ = try UserScriptManager.stageUserScriptImport(fromLocalFile: url)
            fail("mismatched .styl metadata was accepted")
        } catch UserScriptImportError.stylePreprocessorMismatch(let expected, let declared) {
            expect(expected == "stylus" && declared == "less", "wrong mismatch details")
        }
    }

    print("PASS: packaged userstyle compilers")
    finished.signal()
}

while finished.wait(timeout: .now()) == .timedOut {
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
}
