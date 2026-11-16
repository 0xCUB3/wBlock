// Spotify ad media stays playable when the in-page stand-in misses. The
// compatibility exceptions must lift native and DNR blocks for ad media on
// open.spotify.com only, and leave music, other hosts, and non-media loads alone.
import Foundation
import wBlockCoreService

@main
struct Main {
    static func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        exit(1)
    }

    static let adMedia = [
        "https://adstudio-assets.scdn.co/mp3/c4a0aa2af6fb7edb210cf4e54ef8294f60652b48.mp3",
        "https://audio.scdn.co/mp3/ad.mp3",
        "https://p.scdn.co/mp3-ad/ad.mp3",
        "https://track.amillionads.com/a.mp3",
        "https://ads.2mdn.net/a.mp3",
        "https://ads.adxcel.com/a.mp3",
        "https://www.spotify.com/ad-logic/a.mp3",
    ]
    static let spotifyRedirectFilters = [
        "||scdn.co/mp3-ad/", "||scdn.co/mp3/", "||adstudio-assets.scdn.co^", "||amillionads.com^",
        "||2mdn.net^", "||adxcel.com^", "||spotify.com/ad-logic/",
    ]

    static func main() throws {
        let groupIdentifier = "group.wblock.test.spotifyfallback.\(UUID().uuidString.prefix(8))"
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-spotify-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        try nativeBlocks(container: container, groupIdentifier: groupIdentifier)
        try dnrRedirects(container: container)
        print("PASS")
    }

    /// Native blockers, compiled as the app compiles them, for a list of plain
    /// blocks that a generic list would carry for the same hosts.
    static func nativeBlocks(container: URL, groupIdentifier: String) throws {
        let targets = ContentBlockerTargetManager.shared.allTargets(forPlatform: .iOS)
        var filter = FilterList(name: "Ads", url: URL(string: "https://example.com/ads.txt")!, category: .ads, isSelected: true)
        filter.sourceRuleCount = 9
        try """
        ||adstudio-assets.scdn.co^
        ||scdn.co/mp3/
        ||scdn.co/mp3-ad/
        ||amillionads.com^
        ||2mdn.net^
        ||adxcel.com^
        ||spotify.com/ad-logic/
        ||scdn.co/audio/
        ||blocked.example^
        """.write(to: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter)), atomically: true, encoding: .utf8)

        let selection = [filter]
        let ordered = ContentBlockerMappingService.orderedForCompilation(selection)
        let mapping = ContentBlockerMappingService.distribute(selectedFilters: selection, across: targets)
        var blockers: [[[String: Any]]] = []
        for slot in targets {
            _ = try ContentBlockerService.compileTargetRules(
                filters: mapping[slot] ?? [], orderedSelectedFilters: ordered,
                targetInfo: slot, allTargets: targets,
                disabledSites: [], extraRulesText: nil, groupIdentifier: groupIdentifier,
                containerURL: container
            )
            let data = try Data(contentsOf: container.appendingPathComponent(slot.rulesFilename))
            blockers.append(try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? [])
        }

        // The stand-in missed: ad media on Spotify must reach the network.
        for url in adMedia where safariBlocks(url, on: "open.spotify.com", type: "media", in: blockers) {
            fail("ad media must not be blocked on Spotify when the stand-in misses: \(url)")
        }
        // Everywhere else the same loads stay blocked, and so do non-media loads on Spotify.
        for url in adMedia {
            if !safariBlocks(url, on: "page.example", type: "media", in: blockers) {
                fail("ad media on other sites must stay blocked: \(url)")
            }
            if !safariBlocks(url, on: "open.spotify.com", type: "script", in: blockers) {
                fail("the exception covers media only, not scripts: \(url)")
            }
        }
        // Music keeps playing on Spotify, and the list still blocks it elsewhere.
        let song = "https://ap.scdn.co/audio/track.mp3"
        if safariBlocks(song, on: "open.spotify.com", type: "media", in: blockers) {
            fail("music must keep playing on Spotify")
        }
        if !safariBlocks(song, on: "page.example", type: "media", in: blockers) {
            fail("the list's music block must still apply elsewhere")
        }
        // Unrelated blocks are untouched.
        if !safariBlocks("https://blocked.example/x.mp3", on: "open.spotify.com", type: "media", in: blockers) {
            fail("an unrelated block must still apply on Spotify")
        }
    }

    typealias Rule = RemoveParamDNRRuleGenerator.DeclarativeRule

    /// Redirect rules for a list of uBO filters, saved as the extension does.
    static func dnrRedirects(container: URL) throws {
        try """
        ||scdn.co/mp3-ad/$media,redirect=noop-1s.mp4:10,domain=open.spotify.com
        ||scdn.co/mp3/$media,redirect=noop-1s.mp4:10,domain=open.spotify.com
        ||adstudio-assets.scdn.co^$media,redirect=noop-1s.mp4:10,domain=open.spotify.com
        ||amillionads.com^$media,redirect=noop-1s.mp4:10,domain=open.spotify.com
        ||2mdn.net^$media,redirect=noop-1s.mp4:10,domain=open.spotify.com
        ||2mdn.net^$media,redirect=noop-1s.mp4:10,domain=example.com
        ||adxcel.com^$media,redirect=noop-1s.mp4:10,domain=open.spotify.com
        ||spotify.com/ad-logic/$media,redirect=noop-1s.mp4:10,domain=open.spotify.com
        ||ads.example/tag.js$script,redirect=noopjs
        """.write(to: container.appendingPathComponent("Spotify.txt"), atomically: true, encoding: .utf8)
        let filter = FilterList(name: "Spotify", url: URL(string: "https://example.com/Spotify.txt")!, category: .ads, isSelected: true)
        _ = try RemoveParamDNRRuleGenerator.saveRules(
            for: [filter], disabledSites: [], blockedCount: false,
            groupIdentifier: "unused", containerURL: container
        )
        let data = try Data(contentsOf: container.appendingPathComponent(RemoveParamDNRRuleGenerator.rulesFilename))
        let rules = try JSONDecoder().decode([Rule].self, from: data).filter { $0.action.redirect?.extensionPath != nil }

        /// Whether a saved rule redirects `type` loads on `host`.
        func applies(_ rule: Rule, on host: String, type: String) -> Bool {
            func listed(_ sites: [String]?) -> Bool {
                sites?.contains { host == $0 || host.hasSuffix("." + $0) } ?? false
            }
            let condition = rule.condition
            guard condition.resourceTypes?.contains(type) ?? true else { return false }
            return (condition.domains.map(listed) ?? true) && !listed(condition.excludedDomains)
        }
        for filter in spotifyRedirectFilters {
            let saved = rules.filter { $0.condition.urlFilter == filter }
            if saved.contains(where: { applies($0, on: "open.spotify.com", type: "media") }) {
                fail("the Spotify ad redirect \(filter) must not apply to open.spotify.com media")
            }
        }
        if !rules.contains(where: { $0.condition.urlFilter == "||2mdn.net^" && applies($0, on: "example.com", type: "media") }) {
            fail("the exception must not stop the same host's redirect on other sites")
        }
        if !rules.contains(where: { $0.condition.urlFilter == "||ads.example/tag.js" && applies($0, on: "open.spotify.com", type: "script") }) {
            fail("an unrelated redirect must keep its rule")
        }
    }
}
