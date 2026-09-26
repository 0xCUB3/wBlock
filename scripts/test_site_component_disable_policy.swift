import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
@main
struct SiteComponentDisablePolicyTest {
    @MainActor
    static func main() async {
        let master = ["example.com"]
        let filterOnly = ["filter-only.test"]
        let effective = DisabledSitesNormalizer.effectiveFilterDisabledDomains(master: master, filterOnly: filterOnly)

        check(HostMatcher.isHostDisabled(host: "www.example.com", disabledSites: master), "master subdomain should be disabled")
        check(HostMatcher.isHostDisabled(host: "example.com", disabledSites: effective), "master domain should bypass filtering")
        check(effective.contains("filter-only.test"), "filter-only domain should be effective for filtering")
        check(!HostMatcher.isHostDisabled(host: "filter-only.test", disabledSites: master), "filter-only domain must not be globally disabled")
        check(HostMatcher.isHostDisabled(host: "sub.filter-only.test", disabledSites: effective), "filter-only subdomain should bypass filtering")

        // #870: an autoplay exception covers subdomains; the closest entry wins.
        let override = { (host: String) in
            HostMatcher.override(host: host, allowedSites: ["bandcamp.com", "x.blocked.test"], blockedSites: ["loud.bandcamp.com", "blocked.test"])
        }
        check(override("artist.bandcamp.com") == true, "autoplay exception should cover artist subdomains")
        check(override("loud.bandcamp.com") == false, "more specific blocked entry should win")
        check(override("x.blocked.test") == true, "more specific allowed entry should win")
        check(override("notbandcamp.com") == nil, "suffix without a dot boundary must not match")
        check(HostMatcher.override(host: "a.b.test", allowedSites: ["b.test"], blockedSites: ["b.test"]) == false, "blocked wins a tie")

        check(override("https://artist.bandcamp.com/") == true, "URL inputs keep their normalized host semantics")
        check(HostMatcher.override(host: "a.b.test", allowedSites: [" B.TEST "], blockedSites: ["b.test"]) == false, "normalization must precede specificity comparison")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "wblock-autoplay-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let manager = ProtobufDataManager.makeIsolatedForTesting(
            dataDirectoryURL: directory, standardDefaults: defaults, groupDefaults: defaults
        )
        _ = await manager.setNoAutoplayEnabled(true)
        _ = await manager.setAutoplayAllowed(true, onHost: "*.bandcamp.com")
        check(manager.isNoAutoplayEnabled, "site exception must leave global No Autoplay enabled")
        check(manager.isAutoplayAllowed(onHost: "artist.bandcamp.com"), "persisted parent exception covers artists")
        check(!manager.isAutoplayAllowed(onHost: "other.test"), "unrelated hosts keep the global policy")
        _ = await manager.setAutoplayAllowed(false, onHost: "artist.bandcamp.com")
        check(manager.noAutoplayBlockedSites == ["artist.bandcamp.com"], "child can override an allowed parent")
        check(!manager.isAutoplayAllowed(onHost: "artist.bandcamp.com"), "child block overrides parent allow")
        check(manager.isAutoplayAllowed(onHost: "another.bandcamp.com"), "child override must not affect siblings")
        _ = await manager.setAutoplayAllowed(true, onHost: "artist.bandcamp.com")
        check(manager.noAutoplayBlockedSites.isEmpty, "returning to inherited policy removes child override")
        check(manager.noAutoplayAllowedSites == ["bandcamp.com"], "no redundant child allow entry")

        let reloaded = ProtobufDataManager.makeIsolatedForTesting(
            dataDirectoryURL: directory, standardDefaults: defaults, groupDefaults: defaults
        )
        _ = await reloaded.refreshFromDiskIfModified(forceRead: true)
        check(reloaded.isNoAutoplayEnabled, "global policy persists")
        check(reloaded.isAutoplayAllowed(onHost: "artist.bandcamp.com"), "wildcard exception survives reload")
        print("site component disable policy passed")
    }
}
