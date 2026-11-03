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
        var filter = FilterList(
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

        let pageURL = "https://example.com/?utm_source=x&keep=1"
        expectEqual(RemoveParamDNRRuleGenerator.cleanSavedPageURL(pageURL, containerURL: container),
                    "https://example.com/?keep=1", "saved source selectors clean the page")
        filter.excludedSites = ["example.com"]
        _ = try save()
        expectEqual(RemoveParamDNRRuleGenerator.cleanSavedPageURL(pageURL, containerURL: container), pageURL,
                    "per-list exclusion regenerates without changing the source")
        filter.excludedSites = []
        filter.onlySelectedSites = true
        filter.selectedSites = ["other.example"]
        _ = try save()
        expectEqual(RemoveParamDNRRuleGenerator.cleanSavedPageURL(pageURL, containerURL: container), pageURL,
                    "site-only list scope intersects the rule's scope")
        filter.onlySelectedSites = false
        filter.isSelected = false
        expectEqual(try save().removeParamRules, 0, "deselection removes generated rules")
        expectEqual(RemoveParamDNRRuleGenerator.cleanSavedPageURL(pageURL, containerURL: container), pageURL,
                    "deselection clears the page cache")
        filter.isSelected = true
        _ = try save()
        let pageFile = container.appendingPathComponent(RemoveParamDNRRuleGenerator.pageRulesFilename)
        try FileManager.default.removeItem(at: pageFile)
        _ = try save()
        expectEqual(FileManager.default.fileExists(atPath: pageFile.path), true, "missing page selectors regenerate")
        let stateFile = container.appendingPathComponent("dnr-generation-state.json")
        var state = try JSONSerialization.jsonObject(with: Data(contentsOf: stateFile)) as! [String: Any]
        state["schema"] = -1
        try JSONSerialization.data(withJSONObject: state).write(to: stateFile)
        try "[]".write(to: pageFile, atomically: true, encoding: .utf8)
        _ = try save()
        expectEqual(RemoveParamDNRRuleGenerator.cleanSavedPageURL(pageURL, containerURL: container),
                    "https://example.com/?keep=1", "schema invalidation replaces stale selectors")
        print("ok")
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fputs("FAIL: \(message)\nactual: \(String(describing: actual))\nexpected: \(String(describing: expected))\n", stderr)
            exit(1)
        }
    }
}
