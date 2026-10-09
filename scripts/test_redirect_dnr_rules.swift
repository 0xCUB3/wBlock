import Foundation

@main
struct RedirectDNRRuleTests {
    static func main() throws {
        let list = """
        ||ads.example/tag.js$script,redirect=noopjs,domain=site.example|other.*
        ||cdn.example/a.js$redirect=noop.js:5
        ||api.example/x$xhr,redirect=nooptext,important
        ||gone.example/x.js$script,redirect=noopjs
        ||gone.example/x.js$script,redirect=noopjs,badfilter
        ||excepted.example/y.js$script,redirect=noopjs
        @@||excepted.example^$redirect
        ||unknown.example/z$redirect=does-not-exist
        $script,redirect=noopjs
        /regex\\.js/$script,redirect=noopjs
        ||weird.example/w$script,popup,redirect=noopjs
        ||blocked.example/sdk.js$script,redirect-rule=noopjs
        ||blocked.example^
        ||loose.example/sdk.js$script,redirect-rule=noopjs
        ||holed.example/sdk.js$script,redirect-rule=noopjs
        ||holed.example^
        @@||holed.example/sdk.js$domain=x.example
        ||gpt.example/gpt.js$script,redirect=noopjs
        @@||gpt.example/gpt.js$script,redirect=noopjs,domain=news.example
        ||scoped.example/s.js$script,redirect=noopjs,domain=a.example|b.example
        @@||scoped.example^$redirect,domain=a.example
        @@*$redirect-rule,domain=elsewhere.example
        """
        let lines = RemoveParamDNRRuleGenerator.extractRedirectLines(from: list + "\n||unrelated.example^\n")
        expect(!lines.contains("unrelated.example"), "extraction keeps only related blocks")
        expect(lines.contains("||blocked.example^"), "extraction keeps the dependency block")

        let generated = RemoveParamDNRRuleGenerator.generateRules(
            from: "", redirectSources: [lines], disabledSites: ["off.example"]
        )
        let redirects = generated.rules.filter { $0.action.redirect?.extensionPath != nil }
        let byFilter = Dictionary(redirects.map { ($0.condition.urlFilter ?? "", $0) }, uniquingKeysWith: { a, _ in a })
        expectEqual(Set(byFilter.keys), ["||ads.example/tag.js", "||cdn.example/a.js", "||api.example/x", "||blocked.example/sdk.js", "||gpt.example/gpt.js", "||scoped.example/s.js"], "supported directives only")
        expectEqual(generated.summary.resourceRedirectRules, 6, "summary counts redirects")
        let gpt = byFilter["||gpt.example/gpt.js"]!
        expectEqual(gpt.condition.excludedDomains, ["elsewhere.example", "news.example"], "domain-scoped exceptions are subtracted")
        expectEqual(RemoveParamDNRRuleGenerator.carveOutLine(for: gpt), "@@||gpt.example/gpt.js$script,domain=~elsewhere.example|~news.example,important", "carve-out keeps the subtraction")
        expectEqual(byFilter["||scoped.example/s.js"]!.condition.domains, ["b.example"], "excepted inclusion removed")
        expectEqual(byFilter["||scoped.example/s.js"]!.condition.excludedDomains, nil, "never both domains and excludedDomains")

        let ads = byFilter["||ads.example/tag.js"]!
        expectEqual(ads.action.redirect?.extensionPath, "/redirects/noopjs.js", "token resolves to bundled path")
        expectEqual(ads.condition.domains, ["site.example"], "wildcard TLD inclusion dropped, rest kept")
        expectEqual(ads.condition.resourceTypes, ["script"], "explicit type")
        expectEqual(ads.priority, 15_000, "normal priority")
        expectEqual(byFilter["||cdn.example/a.js"]!.condition.resourceTypes, ["script", "xmlhttprequest"], "typeless js narrowed")
        expectEqual(byFilter["||api.example/x"]!.action.redirect?.extensionPath, "/redirects/nooptext.txt", "text stand-in")
        expectEqual(byFilter["||api.example/x"]!.priority, 15_100, "important priority")

        expectEqual(
            RemoveParamDNRRuleGenerator.carveOutLine(for: ads),
            "@@||ads.example/tag.js$script,domain=site.example,important",
            "carve-out mirrors the DNR condition"
        )

        let offAllow = generated.rules.first { $0.priority == 20_000 && $0.condition.domains == ["off.example"] }
        expect(offAllow != nil && offAllow!.condition.resourceTypes == nil, "disabled site allows every subresource")

        let now = Date()
        let good = RemoveParamDNRRuleGenerator.RedirectStatus(installedRedirects: 4, hostAccess: true, privateAccess: true, reportedAt: now)
        expect(RemoveParamDNRRuleGenerator.carveOutsAllowed(status: good, redirectCount: 4, now: now), "healthy status allows carve-outs")
        var bad = good; bad.hostAccess = false
        expect(!RemoveParamDNRRuleGenerator.carveOutsAllowed(status: bad, redirectCount: 4, now: now), "no host access")
        bad = good; bad.privateAccess = nil
        expect(!RemoveParamDNRRuleGenerator.carveOutsAllowed(status: bad, redirectCount: 4, now: now), "unknown private access")
        bad = good; bad.installedRedirects = 3
        expect(!RemoveParamDNRRuleGenerator.carveOutsAllowed(status: bad, redirectCount: 4, now: now), "fewer installed than planned")
        expect(!RemoveParamDNRRuleGenerator.carveOutsAllowed(status: good, redirectCount: 4, now: now.addingTimeInterval(4 * 86_400)), "stale report")
        expect(!RemoveParamDNRRuleGenerator.carveOutsAllowed(status: nil, redirectCount: 4, now: now), "never reported")
        print("redirect DNR rule tests passed")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError("FAIL: \(message)") }
    }

    static func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String) {
        if a != b { fatalError("FAIL: \(message): \(a) != \(b)") }
    }
}
