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
        uriTransformRules()
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

        // Extraction format 2 (before `$uritransform` extraction) is invalidated and rescanned.
        let transformLine = "/^https:\\/\\/(?:www\\.)?instagram\\.com\\/(.*)/$doc,uritransform=//https:\\/\\/kittygr.am\\/$1/\n"
        try transformLine.write(to: container.appendingPathComponent("Test.txt"), atomically: true, encoding: .utf8)
        _ = try RemoveParamDNRRuleGenerator.saveRules(
            for: [filter], disabledSites: [], blockedCount: false, groupIdentifier: "unused", containerURL: container
        )
        var staleTransformCache = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as! [String: [String: Any]]
        staleTransformCache["Test.txt"]!["redirectLines"] = ""
        staleTransformCache["Test.txt"]!["redirectFormat"] = 2
        try JSONSerialization.data(withJSONObject: staleTransformCache).write(to: cacheURL)
        try? FileManager.default.removeItem(at: container.appendingPathComponent("dnr-generation-state.json"))
        let rescannedSummary = try RemoveParamDNRRuleGenerator.saveRules(
            for: [filter], disabledSites: [], blockedCount: false, groupIdentifier: "unused", containerURL: container
        )
        expectEqual(rescannedSummary.resourceRedirectRules, 1, "format bump rescans cached lists for uritransform")
        let rescannedData = try Data(contentsOf: container.appendingPathComponent(RemoveParamDNRRuleGenerator.rulesFilename))
        let rescannedRules = try JSONDecoder().decode([Rule].self, from: rescannedData)
        expectEqual(rescannedRules.first?.action.redirect?.regexSubstitution, "https://kittygr.am/\\1", "rescanned uritransform rule is saved")

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

    static func uriTransformRules() {
        let list = """
        ! Motivating example: instagram -> kittygr.am with a specific-path exception
        /^https:\\/\\/(?:www\\.)?instagram\\.com\\/(.*)/$doc,uritransform=//https:\\/\\/kittygr.am\\/$1/
        @@/^https:\\/\\/(?:www\\.)?instagram\\.com\\/specificpath/$doc,uritransform
        ! Multiple capture groups, escaped comma/dollar/slash, quoted value, match-case, important
        /^https:\\/\\/multi\\.example\\/([^\\/]+)\\/(.*)/$doc,match-case,important,uritransform="//https:\\/\\/dst.example\\/a,b\\/$2\\/$1/"
        ! Exception with matching value and domain/to scoping
        @@/^https:\\/\\/multi\\.example\\/keep/$doc,uritransform=//https:\\/\\/dst.example\\/$1/,domain=caller.example
        ! Badfiltered directive
        /^https:\\/\\/gone\\.example\\/(.*)/$doc,uritransform=//https:\\/\\/other\\.example\\/$1/
        /^https:\\/\\/gone\\.example\\/(.*)/$doc,uritransform=//https:\\/\\/other\\.example\\/$1/,badfilter
        ! Incompatible / skipped forms (must never widen)
        ||instagram.com^$doc,uritransform=//https:\\/\\/kittygr.am\\/$1/
        /^https:\\/\\/nonempty\\.example\\/(.*)/$doc,uritransform=/nonempty\\.example/kittygr.am/
        /^https:\\/\\/unescaped\\.example\\/(.*)/$doc,uritransform=//https://kittygr.am/$1/
        /^https:\\/\\/popup\\.example\\/(.*)/$popup,uritransform=//https:\\/\\/kittygr.am\\/$1/
        /^https:\\/\\/ehide\\.example\\/(.*)/$ehide,uritransform=//https:\\/\\/kittygr.am\\/$1/
        /^https:\\/\\/ping\\.example\\/(.*)/$ping,uritransform=//https:\\/\\/kittygr.am\\/$1/
        /^https:\\/\\/mixed\\.example\\/(.*)/$doc,domain=a.example|~b.example,uritransform=//https:\\/\\/kittygr.am\\/$1/
        /^https:\\/\\/unknown\\.example\\/(.*)/$doc,bogusopt,uritransform=//https:\\/\\/kittygr.am\\/$1/
        /^https:\\/\\/missingval\\.example\\/(.*)/$doc,uritransform
        @@/^https:\\/\\/nonempty-ex\\.example\\/(.*)/$doc,uritransform=/a/b/
        """

        let extracted = RemoveParamDNRRuleGenerator.extractRedirectLines(from: list + "\n||unrelated.example^\n")
        expect(!extracted.contains("unrelated.example"), "uritransform extraction keeps only related lines")
        expect(extracted.contains("kittygr.am"), "uritransform extraction keeps directives")
        expect(extracted.contains("specificpath"), "uritransform extraction keeps exceptions")

        let generated = RemoveParamDNRRuleGenerator.generateRules(
            from: "$removeparam=utm_source\n@@||instagram.com^$removeparam=utm_source",
            redirectSources: [extracted + "\n||ads.example/tag.js$script,redirect=noopjs\n"],
            disabledSites: ["off.example"]
        )
        let transforms = generated.rules.filter { $0.action.redirect?.regexSubstitution != nil }
        expectEqual(transforms.count, 2, "only valid empty-pattern regex uritransforms convert")

        let ig = transforms.first { $0.condition.regexFilter == "^https:\\/\\/(?:www\\.)?instagram\\.com\\/(.*)" }
        expect(ig != nil, "instagram uritransform rule emitted")
        expectEqual(ig?.action.type, "redirect", "uritransform emits redirect action")
        expectEqual(ig?.action.redirect?.regexSubstitution, "https://kittygr.am/\\1", "$1 rewritten to \\1")
        expectEqual(ig?.condition.urlFilter, nil, "uritransform uses regexFilter only")
        expectEqual(ig?.condition.resourceTypes, ["main_frame"], "$doc maps to main_frame")
        expectEqual(ig?.priority, 11_000, "normal uritransform sits above removeparam allows and below redirect stand-ins")
        expectEqual(RemoveParamDNRRuleGenerator.carveOutLine(for: ig!), nil, "uritransform needs no native carve-out")

        let multi = transforms.first { $0.condition.regexFilter == "^https:\\/\\/multi\\.example\\/([^\\/]+)\\/(.*)" }
        expectEqual(multi?.action.redirect?.regexSubstitution, "https://dst.example/a,b/\\2/\\1", "quoted value unescapes and rewrites multiple capture groups")
        expectEqual(multi?.condition.isUrlFilterCaseSensitive, true, "match-case preserved")
        expectEqual(multi?.priority, 13_000, "important uritransform outranks normal exceptions")

        let igAllow = generated.rules.first {
            $0.action.type == "allow" && $0.condition.regexFilter == "^https:\\/\\/(?:www\\.)?instagram\\.com\\/specificpath"
        }
        expect(igAllow != nil, "valueless uritransform exception emits allow rule")
        expectEqual(igAllow?.priority, 12_000, "uritransform exception outranks normal uritransform")
        expectEqual(igAllow?.condition.resourceTypes, ["main_frame"], "exception keeps $doc scope")

        let multiAllow = generated.rules.first {
            $0.action.type == "allow" && $0.condition.regexFilter == "^https:\\/\\/multi\\.example\\/keep"
        }
        expect(multiAllow != nil, "valued uritransform exception emits allow rule")
        expectEqual(multiAllow?.priority, 12_000, "valued exception priority")
        expectEqual(multiAllow?.condition.domains, ["caller.example"], "exception retains domain scope")

        let standIn = generated.rules.first { $0.action.redirect?.extensionPath != nil }
        let removeParam = generated.rules.first { $0.action.redirect?.transform != nil }
        let removeParamAllow = generated.rules.first { $0.action.type == "allow" && $0.condition.urlFilter == "||instagram.com^" }
        let disabledAllow = generated.rules.first { $0.priority == 20_000 }
        expect(removeParam!.priority < removeParamAllow!.priority, "removeparam < removeparam allow")
        expect(removeParamAllow!.priority < ig!.priority, "removeparam allow < uritransform")
        expect(ig!.priority < igAllow!.priority, "uritransform < uritransform allow")
        expect(igAllow!.priority < multi!.priority, "uritransform allow < important uritransform")
        expect(multi!.priority < standIn!.priority, "important uritransform < redirect stand-in")
        expect(standIn!.priority < disabledAllow!.priority, "redirect stand-in < disabled site allow")

        expectEqual(generated.summary.resourceRedirectRules, 3, "summary counts both stand-ins and uritransform redirects")
        expectEqual(generated.summary.skippedRules, 10, "all incompatible uritransform rules reported as skipped")

        // Issue #1176: user-defined RegexRedirectPreference rules (including slash-delimited
        // regex patterns and $N capture groups, plus raw patterns and disabled/invalid rules).
        let mediumRule = RegexRedirectPreference.Rule(
            pattern: #"/^https?:\/\/(?:www\.)?(?:[a-z0-9]+\.)?medium\.com\/(.*)$/"#,
            replacement: "https://scribe.rawbit.ninja/$1",
            isEnabled: true,
            isDocumentOnly: true
        )
        let rawRule = RegexRedirectPreference.Rule(
            pattern: #"^https?://old\.example/([^/]+)/(.*)$"#,
            replacement: #"https://new.example/\2/$1"#,
            isEnabled: true,
            isDocumentOnly: false
        )
        let disabledRule = RegexRedirectPreference.Rule(
            pattern: #"^https?://disabled\.example/(.*)$"#,
            replacement: "https://other.example/$1",
            isEnabled: false
        )
        let invalidRule = RegexRedirectPreference.Rule(
            pattern: #"/[unterminated/"#,
            replacement: "https://other.example/$1",
            isEnabled: true
        )
        expect(RegexRedirectPreference.validationError(pattern: mediumRule.pattern, replacement: mediumRule.replacement) == nil, "medium rule validates")
        expect(RegexRedirectPreference.validationError(pattern: invalidRule.pattern, replacement: invalidRule.replacement) != nil, "invalid regex rejected")

        let customGenerated = RemoveParamDNRRuleGenerator.generateRules(
            from: "",
            regexRedirects: [mediumRule, rawRule, disabledRule, invalidRule]
        )
        expectEqual(customGenerated.rules.count, 2, "only enabled valid regex redirect rules emit")
        let emittedMedium = customGenerated.rules.first { $0.action.redirect?.regexSubstitution == #"https://scribe.rawbit.ninja/\1"# }
        expect(emittedMedium != nil, "Medium -> Scribe rule emitted with \\1 capture group")
        expectEqual(emittedMedium?.condition.regexFilter, #"^https?://(?:www\.)?(?:[a-z0-9]+\.)?medium\.com/(.*)$"#, "slash-delimited regex unescapes \\/")
        expectEqual(emittedMedium?.condition.resourceTypes, ["main_frame"], "document-only regex redirect scopes to main_frame")
        expectEqual(emittedMedium?.condition.isUrlFilterCaseSensitive, true, "slash-delimited regex without /i preserves case sensitivity")

        let emittedRaw = customGenerated.rules.first { $0.action.redirect?.regexSubstitution == #"https://new.example/\2/\1"# }
        expect(emittedRaw != nil, "raw regex redirect mixes \\2 and $1 cleanly")
        expectEqual(emittedRaw?.condition.resourceTypes, nil, "all-requests redirect leaves resourceTypes nil")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError("FAIL: \(message)") }
    }

    static func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String) {
        if a != b { fatalError("FAIL: \(message): \(a) != \(b)") }
    }
}
