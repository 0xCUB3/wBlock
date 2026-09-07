import Foundation
import wBlockCoreService

@main
struct UserScriptPatternBudgetTests {
    static func main() {
        var lines = ["// ==UserScript==", "// @name budget test", "// @run-at document-start"]
        for index in 0..<6_000 {
            lines.append("// @match *://example\(index).invalid/*")
        }
        lines.append("// @match *://namemc.com/*")
        lines.append("// ==/UserScript==")
        let source = lines.joined(separator: "\n") + "\n(() => {})();\n"

        var large = UserScript(name: "large", content: source)
        large.parseMetadata()
        guard large.matches.count == 6_001 else {
            fputs("FAIL: expected 6001 parsed matches, got \(large.matches.count)\n", stderr)
            exit(1)
        }
        guard large.exceedsPersistedPatternBudget else {
            fputs("FAIL: 6k-pattern script should exceed the persisted pattern budget\n", stderr)
            exit(1)
        }

        var small = UserScript(name: "small", content: "// ==UserScript==\n// @match *://a.example/*\n// @match *://b.example/*\n// ==/UserScript==\n")
        small.parseMetadata()
        guard !small.exceedsPersistedPatternBudget else {
            fputs("FAIL: two-pattern script must stay under the budget so its record is unchanged\n", stderr)
            exit(1)
        }

        let trimmed = large.withoutPersistedPatterns()
        guard trimmed.matches.isEmpty, trimmed.excludeMatches.isEmpty,
              trimmed.includes.isEmpty, trimmed.excludes.isEmpty,
              trimmed.id == large.id, trimmed.name == large.name,
              trimmed.runAt == large.runAt, trimmed.content == large.content
        else {
            fputs("FAIL: trimming must clear only the pattern arrays\n", stderr)
            exit(1)
        }
        guard !trimmed.matches(url: "https://namemc.com/x") else {
            fputs("FAIL: a trimmed record must not match on its own; hydration is required\n", stderr)
            exit(1)
        }

        // Re-parsing the source restores the full pattern set, which is what
        // hydrateUserScriptFromDisk does before any matching runs.
        var rehydrated = trimmed
        rehydrated.content = source
        rehydrated.parseMetadata()
        guard rehydrated.matches.count == 6_001,
              rehydrated.matches(url: "https://namemc.com/x"),
              !rehydrated.matches(url: "https://unrelated.invalid/")
        else {
            fputs("FAIL: re-parsing the source must restore matching\n", stderr)
            exit(1)
        }

        print("PASS: userscript persisted pattern budget")
    }
}
