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
        let truncated = G.generateRules(
            from: bulk + "\n@@||site0.example^$removeparam=p0",
            redirectSources: [
                "/^https:\\/\\/(?:www\\.)?instagram\\.com\\/(.*)/$doc,uritransform=//https:\\/\\/kittygr.am\\/$1/\n@@/^https:\\/\\/(?:www\\.)?instagram\\.com\\/specificpath/$doc,uritransform\n"
            ],
            disabledSites: ["disabled.example"]
        )
        check(truncated.rules.count == capacity && truncated.summary.truncatedRules > 0, "bounded DNR generation")
        check(truncated.rules.contains { $0.action.type == "allow" && $0.priority == 10_000 }, "exceptions survive budget pressure")
        check(truncated.rules.contains { $0.action.type == "allow" && $0.priority == 12_000 }, "uritransform exceptions survive budget pressure")
        check(truncated.rules.contains { $0.action.redirect?.regexSubstitution == "https://kittygr.am/\\1" }, "uritransform redirects outrank narrow removeparam rules under budget pressure")
        check(truncated.rules.map(\.id) == Array(G.ruleIDBase..<G.ruleIDBase + capacity), "stable unique rule IDs")
        _ = try JSONEncoder().encode(truncated.rules)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-rp-dnr-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let generated = G.generateRules(from: "$removeparam=utm_source\n||example.com^$removeparam=fbclid").rules
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try FilterArtifactStorage.write(
            encoder.encode(generated),
            to: tempDir.appendingPathComponent(G.rulesFilename)
        )

        let firstPayload = G.loadRulesPayload(containerURL: tempDir, offset: 0, limit: 250, knownVersion: nil)
        let savedVersion = firstPayload["version"] as? String ?? ""
        check((firstPayload["ok"] as? Bool) == true, "initial loadRulesPayload succeeds")
        check(!savedVersion.isEmpty, "saved version is non-empty")
        check((firstPayload["rules"] as? [[String: Any]])?.count == generated.count, "nil knownVersion returns all rules")
        check(firstPayload["unchanged"] == nil, "nil knownVersion omits unchanged flag")

        let unchangedPayload = G.loadRulesPayload(containerURL: tempDir, offset: 0, limit: 250, knownVersion: savedVersion)
        check((unchangedPayload["unchanged"] as? Bool) == true, "matching knownVersion at offset 0 returns unchanged=true")
        check((unchangedPayload["rules"] as? [[String: Any]])?.isEmpty == true, "unchanged payload omits rules array entries")
        check((unchangedPayload["count"] as? Int) == generated.count, "unchanged payload reports exact rule count")
        check((unchangedPayload["version"] as? String) == savedVersion, "unchanged payload reports matching version")

        let stalePayload = G.loadRulesPayload(containerURL: tempDir, offset: 0, limit: 250, knownVersion: "stale-version")
        check((stalePayload["rules"] as? [[String: Any]])?.count == generated.count, "stale knownVersion returns full rules")
        check(stalePayload["unchanged"] == nil, "stale knownVersion omits unchanged flag")

        let offsetPayload = G.loadRulesPayload(containerURL: tempDir, offset: 1, limit: 250, knownVersion: savedVersion)
        check((offsetPayload["rules"] as? [[String: Any]])?.count == max(0, generated.count - 1), "offset > 0 still returns slice even when knownVersion matches")
        check(offsetPayload["unchanged"] == nil, "offset > 0 omits unchanged flag")
        check(!G.hasCachedParsedRules, "final page clears parsed DNR rules from RAM")

        let coldDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-rp-dnr-cold-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: coldDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: coldDir) }
        try FilterArtifactStorage.write(
            encoder.encode(generated),
            to: coldDir.appendingPathComponent(G.rulesFilename)
        )
        let coldHit = G.loadRulesPayload(containerURL: coldDir, offset: 0, limit: 250, knownVersion: savedVersion)
        check((coldHit["unchanged"] as? Bool) == true && (coldHit["count"] as? Int) == generated.count, "cold knownVersion hit succeeds")
        check(!G.hasCachedParsedRules, "cold knownVersion hit skips JSON deserialization")
        check(G.savedRulesCount(containerURL: coldDir) == generated.count && !G.hasCachedParsedRules, "savedRulesCount reads count without caching parsed rules")

        check(generated.count >= 2, "expected at least 2 generated rules for multi-page test")
        let page0 = G.loadRulesPayload(containerURL: coldDir, offset: 0, limit: 1, knownVersion: nil)
        check((page0["rules"] as? [[String: Any]])?.count == 1 && G.hasCachedParsedRules, "non-final page retains parsed rules for subsequent chunks")
        let page1 = G.loadRulesPayload(containerURL: coldDir, offset: 1, limit: generated.count, knownVersion: nil)
        check((page1["rules"] as? [[String: Any]])?.count == generated.count - 1 && !G.hasCachedParsedRules, "final page releases parsed rules")

        let corruptDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-rp-dnr-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: corruptDir) }
        let corruptData = Data("{not-json".utf8)
        try FilterArtifactStorage.write(corruptData, to: corruptDir.appendingPathComponent(G.rulesFilename))
        let corruptVersion = DigestSupport.sha256Hex(corruptData)
        let corruptPayload = G.loadRulesPayload(containerURL: corruptDir, offset: 0, limit: 250, knownVersion: corruptVersion)
        check((corruptPayload["ok"] as? Bool) == false, "corrupt JSON still returns ok=false even when knownVersion matches its digest")
        check(!G.hasCachedParsedRules, "corrupt JSON never caches failed parse")

        let emptyBase = G.emptyRulesPayload(offset: 0, limit: 250)
        let emptyVersion = emptyBase["version"] as? String ?? ""
        let emptyUnchanged = G.emptyRulesPayload(offset: 0, limit: 250, knownVersion: emptyVersion)
        check((emptyUnchanged["unchanged"] as? Bool) == true, "emptyRulesPayload sets unchanged=true when knownVersion matches")

        // Verify parsedRules detects a concurrent file rewrite between loadHeader and parsedRules.
        let raceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-rp-dnr-race-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: raceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: raceDir) }
        let raceFile = raceDir.appendingPathComponent(G.rulesFilename)
        let raceV1 = G.generateRules(from: "$removeparam=utm_source").rules
        let raceV2 = G.generateRules(from: "$removeparam=utm_source\n||example.com^$removeparam=fbclid").rules
        let raceData1 = try encoder.encode(raceV1)
        let raceData2 = try encoder.encode(raceV2)
        try FilterArtifactStorage.write(raceData1, to: raceFile)
        let raceCache = G.SavedRuleFileCache()
        let initialLoad = raceCache.loadHeader(at: raceFile)
        check(initialLoad != nil, "race test initial header loads")
        let cachedLoad = raceCache.loadHeader(at: raceFile)
        check(cachedLoad != nil && cachedLoad?.rawData == nil, "race test cached header omits rawData")
        try FilterArtifactStorage.write(raceData2, to: raceFile)
        let parsedAfterRewrite = raceCache.parsedRules(at: raceFile, header: cachedLoad!.header, rawData: nil)
        let expectedV2Version = DigestSupport.sha256Hex(raceData2)
        check(parsedAfterRewrite?.header.version == expectedV2Version, "parsedRules returns fresh version after concurrent rewrite")
        check(parsedAfterRewrite?.rules.count == raceV2.count, "parsedRules returns fresh rules matching fresh version")

        print("PASS removeparam selectors, scopes, exceptions, badfilter and DNR capacity")
    }
}
