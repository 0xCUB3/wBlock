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

        plainExceptions()
        try savedRules()
        print("redirect DNR rule tests passed")
    }

    typealias Rule = RemoveParamDNRRuleGenerator.DeclarativeRule

    /// Redirect rules resolved from `lists`, each extracted as its own list, by URL filter.
    static func redirects(_ lists: String...) -> [String: Rule] {
        let sources = lists.map { RemoveParamDNRRuleGenerator.extractRedirectLines(from: $0) }
        let rules = RemoveParamDNRRuleGenerator.generateRules(from: "", redirectSources: sources).rules
        return Dictionary(
            rules.filter { $0.action.redirect?.extensionPath != nil }.map { ($0.condition.urlFilter ?? "", $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// A blocking exception stops the redirect of the requests it covers, and nothing else.
    static func plainExceptions() {
        let directives = """
        ||cdn.example/lib.js$script,redirect=noopjs
        ||media.example/audio/$media,redirect=noop-1s.mp4,domain=player.example
        ||media.example/audio/$script,redirect=noopjs,domain=player.example
        ||media.example/mp3/$media,redirect=noop-1s.mp4,domain=player.example
        ||ads.media.example^$media,redirect=noop-1s.mp4,domain=player.example
        ||tags.example/gpt.js$script,redirect=noopjs
        ||typeless.example/a.js$redirect=noopjs
        ||party.example/t.js$script,redirect=noopjs
        ||adhost.example/tag.js$script,redirect=noopjs
        ||static.site.example/app.js$script,redirect=noopjs
        ||firm.example/x.js$script,redirect=noopjs,important
        ||firmer.example/x.js$script,redirect=noopjs,important
        ||revived.example/x.js$script,redirect=noopjs
        ||cosmetic.example/x.js$script,redirect=noopjs
        ||wide.example^$script,redirect=noopjs
        ||wild.example/v2/sdk.js$script,redirect=noopjs
        ||wild.example/v2/other.js$script,redirect=noopjs
        ||hit.metrics.example/g.js$script,redirect=noopjs
        """
        let exceptions = """
        @@||cdn.example^
        @@||media.example/audio/$media,domain=player.example
        @@||tags.example/gpt.js$script,domain=news.example
        @@||typeless.example/a.js$script
        @@||party.example/t.js$third-party
        @@*$script,1p,domain=site.example
        @@*$script,domain=entity.*
        @@||firm.example^$script
        @@||firmer.example^$script,important
        @@||revived.example^$script
        @@||cosmetic.example^$elemhide
        @@||cosmetic.example^$document
        @@||cosmetic.example^$csp=script-src 'self'
        @@||wide.example/keep.js$script
        @@||wild.example/*/sdk.js$script
        @@||metrics.example/g.js
        """
        let kept = RemoveParamDNRRuleGenerator.extractRedirectLines(from: exceptions)
        expect(kept.contains("@@||cdn.example^\n"), "extraction keeps an exception from a list with no redirect")
        expect(!kept.contains("elemhide") && !kept.contains("csp"), "extraction drops exceptions from other than blocking")

        let rules = redirects(directives, exceptions, "@@||revived.example^$script,badfilter")
        expectEqual(Set(rules.keys), [
            "||media.example/audio/", "||media.example/mp3/", "||ads.media.example^", "||tags.example/gpt.js",
            "||typeless.example/a.js", "||party.example/t.js", "||adhost.example/tag.js",
            "||static.site.example/app.js", "||firm.example/x.js", "||revived.example/x.js",
            "||cosmetic.example/x.js", "||wide.example^", "||wild.example/v2/other.js",
        ], "exceptions drop only the directives they cover")
        expectEqual(redirects(directives).count, 17, "every directive resolves without the exceptions")
        expectEqual(redirects(directives)["||media.example/audio/"]!.condition.resourceTypes, ["media"], "the media directive resolves without its exception")
        expectEqual(rules["||media.example/audio/"]!.condition.resourceTypes, ["script"], "a media exception leaves the script directive")

        let tags = rules["||tags.example/gpt.js"]!
        expectEqual(tags.condition.excludedDomains, ["news.example"], "a scoped exception is subtracted")
        expectEqual(RemoveParamDNRRuleGenerator.carveOutLine(for: tags), "@@||tags.example/gpt.js$script,domain=~news.example,important", "the carve-out leaves the excepted site blocked")
        expectEqual(rules["||typeless.example/a.js"]!.condition.resourceTypes, ["xmlhttprequest"], "an excepted type is removed")
        expectEqual(rules["||party.example/t.js"]!.condition.domainType, "firstParty", "an excepted party is removed")
        expectEqual(rules["||adhost.example/tag.js"]!.condition.excludedDomains, nil, "a first-party exception leaves another site's host")
        expectEqual(rules["||adhost.example/tag.js"]!.condition.resourceTypes, ["script"], "a site the condition cannot name is not taken as every site")
        expectEqual(rules["||static.site.example/app.js"]!.condition.excludedDomains, ["site.example"], "a first-party exception covers the site's own host")
        expectEqual(rules["||firm.example/x.js"]!.priority, 15_100, "important outranks an exception")

        let js = "||cdn.example/a.js$redirect=noopjs"
        func unchanged(_ directive: String, _ exception: String, _ message: String) {
            expectEqual(redirects(directive, exception), redirects(directive), message)
        }
        unchanged(js, "@@||cdn.example^$domain=~keep.example", "negative site scope is not global")
        unchanged(js, "@@||cdn.example^$domain=site.example|~keep.site.example", "mixed site scope is not widened")
        unchanged(js, "@@||cdn.example^$script,domain=site.example", "scoped partial type leaves other types intact")
        unchanged("foo$redirect=noopjs", "@@*$1p,domain=site.example", "unknown host does not widen scoped party")
        unchanged(js, "@@||cdn.example^$script,1p", "partial type and party do not remove other parties")
        unchanged("||cdn.example/audio$media,redirect=noop-1s.mp4", "@@||cdn.example/audio^$media", "separator does not cover a URL prefix")
        unchanged("||cdn.example^x$script,redirect=noopjs", "@@||cdn.example/x$script", "literal separator does not cover separator wildcard")
        unchanged("||cdn.example/audio/$media,redirect=noop-1s.mp4", "@@||cdn.example/Audio/$media,match-case", "case-sensitive exception is not widened")
        unchanged("||cdn.example/a.js$script,redirect=noopjs,domain=example.com", "@@||cdn.example^$script,domain=sub.example.com", "partial site subtraction preserves the parent scope")
    }

    /// The saved rules honor the built-in compatibility exceptions, and a
    /// cache written before plain exceptions were extracted is rescanned.
    static func savedRules() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("redirect-dnr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        try """
        ||scdn.co/audio/$media,redirect=noop-1s.mp4:10,domain=open.spotify.com
        ||scdn.co/mp3-ad/$media,redirect=noop-1s.mp4:10,domain=open.spotify.com
        ||adstudio-assets.scdn.co^$media,redirect=noop-1s.mp4:10,domain=open.spotify.com
        ||cdn.example/lib.js$script,redirect=noopjs
        @@||cdn.example^
        """.write(to: container.appendingPathComponent("Test.txt"), atomically: true, encoding: .utf8)
        let filter = FilterList(
            name: "Test", url: URL(string: "https://example.com/Test.txt")!, category: .ads, isSelected: true
        )
        func savedFilters(disabledSites: [String] = []) throws -> Set<String> {
            _ = try RemoveParamDNRRuleGenerator.saveRules(
                for: [filter], disabledSites: disabledSites, blockedCount: false,
                groupIdentifier: "unused", containerURL: container
            )
            let data = try Data(contentsOf: container.appendingPathComponent(RemoveParamDNRRuleGenerator.rulesFilename))
            return Set(try JSONDecoder().decode([Rule].self, from: data)
                .filter { $0.action.redirect?.extensionPath != nil }.compactMap(\.condition.urlFilter))
        }
        // Every Spotify ad redirect is excepted for open.spotify.com media, so none is saved.
        let expected: Set<String> = []
        expectEqual(try savedFilters(), expected, "compatibility exceptions stop the redirect of the audio they allow")

        // The cache as an earlier build left it: no format, and no plain exception.
        let cacheURL = container.appendingPathComponent("dnr-extraction-cache.json")
        var cache = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as! [String: [String: Any]]
        let lines = cache["Test.txt"]!["redirectLines"] as! String
        expect(lines.contains("@@||cdn.example^"), "the extraction cache holds the plain exception")
        cache["Test.txt"]!["redirectLines"] = lines.replacingOccurrences(of: "@@||cdn.example^\n", with: "")
        cache["Test.txt"]!["redirectFormat"] = nil
        try JSONSerialization.data(withJSONObject: cache).write(to: cacheURL)
        expectEqual(try savedFilters(disabledSites: ["off.example"]), expected, "an older extraction cache is rescanned")

        try "@@||cdn.example^$script\n".write(to: container.appendingPathComponent("Scoped.txt"), atomically: true, encoding: .utf8)
        var scoped = FilterList(name: "Scoped", url: URL(string: "https://example.com/Scoped.txt")!, category: .ads, isSelected: true)
        scoped.onlySelectedSites = true
        scoped.selectedSites = ["site.example"]
        try "||cdn.example/lib.js$script,redirect=noopjs\n".write(to: container.appendingPathComponent("Test.txt"), atomically: true, encoding: .utf8)
        _ = try RemoveParamDNRRuleGenerator.saveRules(for: [filter, scoped], disabledSites: [], blockedCount: false, groupIdentifier: "unused", containerURL: container)
        let data = try Data(contentsOf: container.appendingPathComponent(RemoveParamDNRRuleGenerator.rulesFilename))
        let scopedRules = try JSONDecoder().decode([Rule].self, from: data)
        expect(scopedRules.contains { $0.condition.urlFilter == "||cdn.example/lib.js" && $0.action.redirect?.extensionPath != nil }, "a scoped list's exception is not global")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError("FAIL: \(message)") }
    }

    static func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String) {
        if a != b { fatalError("FAIL: \(message): \(a) != \(b)") }
    }
}
