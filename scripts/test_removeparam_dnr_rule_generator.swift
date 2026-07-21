import Foundation

@main
struct RemoveParamDNRRuleGeneratorTests {
    static func main() throws {
        let rulesText = """
        ! comment
        $removeparam=utm_source
        ||example.com^$removeparam=fbclid
        @@||example.com^$removeparam=fbclid
        ||example.org^$removeparam
        ||bad.example^$removeparam=/^utm_/
        ||bad.example^$removeparam=~keep
        ||encoded.example^$removeparam=%24param,script,domain=foo.example|~bar.example
        ||typed.example^$xmlhttprequest,removeparam=id,third-party
        $removeparam=v,hinta.fi|carrefoursa.com
        """

        let generated = RemoveParamDNRRuleGenerator.generateRules(
            from: rulesText,
            disabledSites: ["Disabled.example", "bad host"]
        )
        let rules = generated.rules
        let summary = generated.summary

        expectEqual(summary.removeParamRules, 9, "source removeparam count")
        expectEqual(summary.exceptionRules, 1, "exception count")
        expectEqual(summary.skippedRules, 3, "unsupported rules skipped")
        expectEqual(summary.disabledSiteAllowRules, 2, "disabled-site allow rules")
        expectEqual(summary.generatedRules, 8, "generated DNR rule count")

        let disabledByRequestDomain = rules[0]
        expectEqual(disabledByRequestDomain.action.type, "allow", "disabled request-domain allow")
        expectEqual(disabledByRequestDomain.priority, 20_000, "disabled allow priority")
        expectEqual(disabledByRequestDomain.condition.requestDomains, ["disabled.example"], "disabled request domain")

        let generic = rules[2]
        expectEqual(generic.action.type, "redirect", "generic action")
        expectEqual(generic.action.redirect?.transform.queryTransform?.removeParams, ["utm_source"], "generic remove param")
        expectEqual(generic.condition.urlFilter, "^utm_source=", "generic param-aware filter")
        expectEqual(generic.condition.resourceTypes, ["main_frame", "sub_frame"], "default document resources")

        let scoped = rules[3]
        expectEqual(scoped.condition.urlFilter, "||example.com^*^fbclid=", "scoped param-aware filter")

        let exception = rules[4]
        expectEqual(exception.action.type, "allow", "exception action")
        expectEqual(exception.priority, 10_000, "exception priority")
        expectEqual(exception.condition.urlFilter, "||example.com^*^fbclid=", "exception filter")

        let stripAll = rules[5]
        expectEqual(stripAll.action.redirect?.transform.query, "", "strip-all query transform")
        expectEqual(stripAll.condition.urlFilter, "||example.org^", "strip-all filter")

        let encoded = rules[6]
        expectEqual(encoded.action.redirect?.transform.queryTransform?.removeParams, ["$param"], "encoded param decoded")
        expectEqual(encoded.condition.resourceTypes, ["script"], "explicit resource type")
        expectEqual(encoded.condition.initiatorDomains, ["foo.example"], "included domain")
        expectEqual(encoded.condition.excludedInitiatorDomains, ["bar.example"], "excluded domain")

        let typed = rules[7]
        expectEqual(typed.condition.resourceTypes, ["xmlhttprequest"], "xmlhttprequest resource type")
        expectEqual(typed.condition.domainType, "thirdParty", "third-party domain type")

        let encoder = JSONEncoder()
        _ = try encoder.encode(rules)

        print("ok")
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fputs("FAIL: \(message)\nactual: \(String(describing: actual))\nexpected: \(String(describing: expected))\n", stderr)
            exit(1)
        }
    }
}
