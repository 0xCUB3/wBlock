import Foundation
@testable import wBlockCoreService

@main struct RemoveParamDNRRuleGeneratorTests {
    typealias G = RemoveParamDNRRuleGenerator
    static func main() throws {
        func check(_ value: Bool, _ message: String) {
            if !value { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        func clean(_ rules: String, _ url: String, _ expected: String) {
            let actual = G.cleanPageURL(url, rules: G.generatePageRules(from: rules))
            check(actual == expected, "\(rules) cleaned \(url) to \(actual), expected \(expected)")
        }
        let url = "https://example.com/?utm_source=x&utm_medium=y&fbclid=z&keep=1"
        let trackers = "$doc,removeparam=/^\\??utm_.*$/i,domain=~transfernow.*\n$removeparam=fbclid"
        clean(trackers, url, "https://example.com/?keep=1")
        for host in ["transfernow.net", "www.transfernow.net", "transfernow.co.uk"] {
            clean(trackers, "https://\(host)/?utm_source=x&fbclid=z&keep=1", "https://\(host)/?utm_source=x&keep=1")
        }
        clean(trackers, "https://transfernow.evil.com/?utm_unknown=x", "https://transfernow.evil.com/")
        clean("$removeparam=/^utm_/i", "https://example.com/?UTM_NEW=x&keep=%2f+%20#hash", "https://example.com/?keep=%2f+%20#hash")
        clean("$removeparam=/^amp=true$/", "https://example.com/?amp=true&amp=false&keep=1", "https://example.com/?amp=false&keep=1")
        clean("$removeparam=/^x=a,b$/", "https://example.com/?x=a%2Cb&x=c", "https://example.com/?x=c")
        clean("$removeparam=/^x=a\\,b$/", "https://example.com/?x=a%2Cb", "https://example.com/")
        clean("$removeparam=/^x=a{2,3}$/", "https://example.com/?x=aaa&x=a", "https://example.com/?x=a")
        clean("$removeparam=~keep", "https://example.com/?novel=x&keep=%2B&bare#x", "https://example.com/?keep=%2B#x")
        clean("$removeparam=~/^(keep|id)=/", "https://example.com/?novel=x&keep=1&id=2", "https://example.com/?keep=1&id=2")
        clean("$removeparam=/^(?!keep=)/", "https://example.com/?novel=x&keep=1", "https://example.com/?keep=1")
        clean("||example.com^$removeparam", url, "https://example.com/")
        clean("$removeparam=|", url, "https://example.com/")
        clean("$removeparam=x", "https://example.com/?x&x=2&X=3&%78=4", "https://example.com/?X=3&%78=4")
        clean("$removeparam=%78", "https://example.com/?x&%78=4", "https://example.com/?x")
        clean("$removeparam=x", "https://example.com/#?x=2", "https://example.com/#?x=2")
        clean("fragment$removeparam=x", "https://example.com/?x=1#fragment", "https://example.com/?x=1#fragment")
        clean("$removeparam=x\n@@$removeparam=|", "https://example.com/?x=1", "https://example.com/")
        clean("$removeparam=x\n@@/subscribe?$doc,removeparam=x\n$removeparam=y", "https://example.com/subscribe?x=1&y=2", "https://example.com/subscribe?x=1")
        check(G.generateRules(from: "@@/subscribe?$doc,removeparam=x").rules.first?.condition.urlFilter == "/subscribe?", "DNR exceptions do not narrow past the first query separator")
        clean("$removeparam=x\n@@||example.com^$removeparam=x\n$removeparam=y", "https://example.com/?x=1&y=2", "https://example.com/?x=1")
        clean("$removeparam=x\n@@||example.com^$removeparam", "https://example.com/?x=1", "https://example.com/?x=1")
        clean("$removeparam=x,important\n@@||example.com^$removeparam", "https://example.com/?x=1", "https://example.com/")
        // uBO exceptions cancel the same modifier value, not every selector that
        // happens to match a parameter with that name.
        clean("$removeparam=/^x=/\n@@$removeparam=x", "https://example.com/?x=1", "https://example.com/")
        clean("$removeparam=/^x=/\n@@$removeparam=/^x=/", "https://example.com/?x=1", "https://example.com/?x=1")
        clean("$doc,removeparam=x\n$removeparam=x,badfilter,doc", "https://example.com/?x=1", "https://example.com/?x=1")
        clean("$removeparam=x\n@@$removeparam=x\n@@$removeparam=x,badfilter", "https://example.com/?x=1", "https://example.com/")
        clean("$removeparam=x,domain=example.*|~www.example.com", "https://example.co.uk/?x=1", "https://example.co.uk/")
        clean("$removeparam=x,domain=example.*|~www.example.com", "https://www.example.com/?x=1", "https://www.example.com/?x=1")
        clean("$removeparam=x,to=example.*", "https://example.com/?x=1", "https://example.com/")
        clean("$removeparam=x,denyallow=example.com", "https://example.com/?x=1", "https://example.com/?x=1")
        clean("$removeparam=x,from=example.com,1p", "https://example.com/?x=1", "https://example.com/")
        clean("$removeparam=x,3p", "https://example.com/?x=1", "https://example.com/?x=1")
        clean("$removeparam=x,xhr", "https://example.com/?x=1", "https://example.com/?x=1")
        clean("$removeparam=x,~doc", "https://example.com/?x=1", "https://example.com/?x=1")
        clean("$removeparam=x,~xhr", "https://example.com/?x=1", "https://example.com/")
        clean("/example\\.com/.*\\?/$removeparam=x", "https://example.com/?x=1", "https://example.com/")
        clean("/example\\.org/.*\\?/$removeparam=x", "https://example.com/?x=1", "https://example.com/?x=1")
        clean("|https://example.com/?x=1|$removeparam=x", "https://example.com/?x=12", "https://example.com/?x=12")
        clean("$removeparam=x,unknown", "https://example.com/?x=1", "https://example.com/?x=1")

        clean("/^http.*[^?]\\?$/$doc,removeparam=/^=$/", "https://example.com/?", "https://example.com/")
        let methods = G.generateRules(from: "||snappfood.ir^$xhr,1p,method=get,removeparam=deviceType")
        check(methods.rules.first?.condition.requestMethods == ["get"], "Safari 26 method conditions remain explicit")
        check(!G.generateRules(from: "||hktvmall.com/yuicombo?$script,removeparam=/_ui/shared/common/js/analytics/with-intersection-track.js").rules.isEmpty, "slash-prefixed literal is not a malformed regex")
        let entityException = G.generateRules(from: "$removeparam=x\n@@/search-redirection$doc,removeparam,domain=audible.*")
        check(entityException.rules.count == 2 && entityException.rules[0].action.type == "redirect" &&
              entityException.rules[1].condition.urlFilter == "/search-redirection", "entity exception retains its URL scope without suppressing unrelated transforms")
        clean("$removeparam=x\n@@/search-redirection$doc,removeparam,domain=audible.*", "https://example.com/search-redirection?x=1", "https://example.com/search-redirection")
        clean("$removeparam=x\n@@/search-redirection$doc,removeparam,domain=audible.*", "https://audible.co.uk/search-redirection?x=1", "https://audible.co.uk/search-redirection?x=1")
        let dnr = G.generateRules(from: "$removeparam=x\n||example.org^$removeparam\n||api.example^$xhr,3p,removeparam=y\n$removeparam=z,~doc")
        check(dnr.summary.skippedRules == 0 && dnr.rules.count == 4, "literals, all, aliases and negated types admitted")
        check(dnr.rules[1].action.redirect?.transform?.query == "", "strip-all uses empty query")
        check(dnr.rules[2].condition.domainType == "thirdParty" && dnr.rules[2].condition.resourceTypes == ["xmlhttprequest"], "XHR party scope retained")
        check(dnr.rules[3].condition.resourceTypes?.contains("main_frame") == false, "negated document retained")
        check(G.generateRules(from: "$removeparam=x\n$removeparam=x,badfilter").rules.isEmpty, "badfilter cancels DNR")
        let regex = G.generateRules(from: "$doc,removeparam=/^utm_.*$/i")
        check(regex.rules.count == 19 && regex.rules.allSatisfy { $0.condition.urlFilter?.hasPrefix("^utm_") == true }, "expanded regex names cannot shadow unrelated redirects")
        check(G.generateRules(from: "$removeparam=/^amp=true$/").rules.isEmpty, "value-specific regex never strips every amp value in DNR")
        check(G.generateRules(from: "$removeparam=x,domain=~transfernow.*").rules.isEmpty, "entity scope goes to PSL-aware page evaluator")
        let pattern = G.generateRules(from: "/example\\.com/$removeparam=x").rules.first
        check(pattern?.condition.regexFilter == "example\\.com" && pattern?.condition.urlFilter == nil, "URL regex cannot become an unscoped redirect")
        let scoped = G.generateRules(from: "$removeparam=x,domain=page.example|~except.example,to=target.example|~except-target.example").rules.first
        check(scoped?.condition.domains == ["page.example"] && scoped?.condition.excludedRequestDomains == ["except-target.example"], "both domain scopes retained")
        let capacity = G.maxGeneratedRules
        let bulk = (0..<capacity + 1).map { "||site\($0).example^$removeparam=p\($0)" }.joined(separator: "\n")
        let truncated = G.generateRules(from: bulk + "\n@@||site0.example^$removeparam=p0", disabledSites: ["disabled.example"])
        check(truncated.rules.count == capacity && truncated.summary.truncatedRules > 0, "bounded DNR generation")
        check(truncated.rules.contains { $0.action.type == "allow" && $0.priority == 10_000 }, "exceptions survive budget pressure")
        check(truncated.rules.map(\.id) == Array(G.ruleIDBase..<G.ruleIDBase + capacity), "stable unique rule IDs")
        _ = try JSONEncoder().encode(truncated.rules)
        print("PASS removeparam selectors, scopes, exceptions, badfilter and DNR capacity")
    }
}
