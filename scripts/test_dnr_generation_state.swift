import Foundation
@testable import wBlockCoreService

/// The saved removeparam rules are reused while their inputs are unchanged.
/// A changed source, changed disabled sites, a missing rules file, or a clear
/// must each regenerate them.
@main
struct DNRGenerationStateTests {
    static func main() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("dnr-generation-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let source = container.appendingPathComponent("Test.txt")
        try "||example.com^$removeparam=utm_source\n".write(to: source, atomically: true, encoding: .utf8)
        let filter = FilterList(
            name: "Test", url: URL(string: "https://example.com/Test.txt")!,
            category: .ads, isSelected: true
        )
        let rulesURL = container.appendingPathComponent(RemoveParamDNRRuleGenerator.rulesFilename)

        func save(_ disabledSites: [String] = []) throws -> RemoveParamDNRRuleGenerator.Summary {
            try RemoveParamDNRRuleGenerator.saveRules(
                for: [filter], disabledSites: disabledSites, blockedCount: false,
                groupIdentifier: "unused", containerURL: container
            )
        }
        func rulesText() throws -> String { try String(contentsOf: rulesURL, encoding: .utf8) }

        let first = try save()
        expectEqual(first.removeParamRules, 1, "first generation reads the source")
        expectEqual(try rulesText().contains("utm_source"), true, "first generation writes the rule")

        let unchanged = try rulesText()
        expectEqual(try save(), first, "unchanged inputs give the same summary")
        expectEqual(try rulesText(), unchanged, "unchanged inputs keep the saved rules")

        try "||example.com^$removeparam=utm_source\n||other.example^$removeparam=fbclid\n".write(
            to: source, atomically: true, encoding: .utf8
        )
        let changed = try save()
        expectEqual(changed.removeParamRules, 2, "a changed source regenerates")
        expectEqual(try rulesText().contains("fbclid"), true, "a changed source writes its new rule")

        let withSite = try save(["example.org"])
        expectEqual(withSite.disabledSiteAllowRules > 0, true, "changed disabled sites regenerate")

        try FileManager.default.removeItem(at: rulesURL)
        _ = try save(["example.org"])
        expectEqual(FileManager.default.fileExists(atPath: rulesURL.path), true, "a missing rules file is rewritten")

        _ = try RemoveParamDNRRuleGenerator.clearSavedRules(containerURL: container)
        expectEqual(try rulesText(), "[]", "clear empties the rules")
        let afterClear = try save(["example.org"])
        expectEqual(afterClear, withSite, "the first apply after a clear regenerates the rules")
        expectEqual(try rulesText().contains("fbclid"), true, "the first apply after a clear restores the rules")

        print("ok")
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fputs("FAIL: \(message)\nactual: \(String(describing: actual))\nexpected: \(String(describing: expected))\n", stderr)
            exit(1)
        }
    }
}
