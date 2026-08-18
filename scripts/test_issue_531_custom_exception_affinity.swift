import Foundation
import wBlockCoreService

// Issue #531: a plain @@ exception rule in a custom filter only reached the one
// content blocker slot the custom list was assigned to, so it could not cancel
// block rules compiled into the other four extensions. Custom-filter exception
// rules must be replicated to every target automatically, without users having
// to wrap them in !#safari_cb_affinity(all) by hand.
@main
struct Issue531CustomExceptionAffinityTests {
    static func main() throws {
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)
        let adsTarget = targets[0]
        let privacyTarget = targets[1]
        let customTarget = targets[4]

        let customFilter = FilterList(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000531")!,
            name: "Custom",
            url: URL(string: "https://example.com/custom.txt")!,
            category: .custom,
            isCustom: true
        )
        let builtinFilter = FilterList(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000532")!,
            name: "Builtin",
            url: URL(string: "https://example.com/builtin.txt")!,
            category: .ads
        )

        let exceptionRule = "@@||log.strm.yandex.ru^$domain=yandex.ru"
        let source = """
        ||blocked.example^
        \(exceptionRule)
        !#safari_cb_affinity(privacy)
        ||privacy-only.example^
        !#safari_cb_affinity
        """

        // Custom filters with plain exception rules join the affinity pipeline.
        guard let content = SafariContentBlockerAffinityProcessor.affinitySourceContent(
            for: customFilter,
            rawContent: source
        ) else {
            fail("custom filter with a top-level @@ rule must produce affinity content")
        }

        // Built-in filters keep the existing directive-only behavior.
        expect(
            SafariContentBlockerAffinityProcessor.affinitySourceContent(
                for: builtinFilter,
                rawContent: "||a.example^\n@@||b.example^"
            ) == nil,
            "non-custom filters without directives must stay out of the affinity pipeline"
        )
        expect(
            SafariContentBlockerAffinityProcessor.affinitySourceContent(
                for: builtinFilter,
                rawContent: source
            ) == source,
            "non-custom filters with explicit directives must keep their raw content"
        )
        expect(
            SafariContentBlockerAffinityProcessor.affinitySourceContent(
                for: customFilter,
                rawContent: "||only-blocks.example^"
            ) == nil,
            "custom filters without exceptions or directives must stay out of the affinity pipeline"
        )

        // The assigned target keeps base rules and the exception.
        let assigned = SafariContentBlockerAffinityProcessor.filteredContent(
            from: content,
            includeBaseRules: true,
            target: customTarget,
            allTargets: targets
        )
        expect(assigned.contains("||blocked.example^"), "assigned target must keep base block rules")
        expect(assigned.contains(exceptionRule), "assigned target must keep the exception rule")
        expect(!assigned.contains("||privacy-only.example^"), "assigned target must not receive privacy-affinity rules")

        // Every other target receives the exception rule, but no base rules.
        let other = SafariContentBlockerAffinityProcessor.filteredContent(
            from: content,
            includeBaseRules: false,
            target: adsTarget,
            allTargets: targets
        )
        expect(other == exceptionRule, "other targets must receive exactly the exception rule")

        // Explicit affinity blocks authored by the user stay intact.
        let privacy = SafariContentBlockerAffinityProcessor.filteredContent(
            from: content,
            includeBaseRules: false,
            target: privacyTarget,
            allTargets: targets
        )
        expect(privacy.contains("||privacy-only.example^"), "explicit privacy affinity block must be preserved")
        expect(privacy.contains(exceptionRule), "privacy target must also receive the replicated exception")
        expect(!privacy.contains("||blocked.example^"), "privacy target must not receive base block rules")

        print("PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
