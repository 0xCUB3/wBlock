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
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let manager = ProtobufDataManager.makeIsolatedForTesting(
            dataDirectoryURL: directory
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
            dataDirectoryURL: directory
        )
        _ = await reloaded.refreshFromDiskIfModified(forceRead: true)
        check(reloaded.isNoAutoplayEnabled, "global policy persists")
        check(reloaded.isAutoplayAllowed(onHost: "artist.bandcamp.com"), "wildcard exception survives reload")
        // A whole-site edit uses the existing preferences, including an empty zapper rule set.
        _ = await manager.setNoAutoplayEnabled(false)
        let host = "whole.test"
        await manager.setFilterDisabledDomains([host])
        check(!manager.areAllSiteComponentsDisabled(onHost: host), "filter-only must remain a mixed state")
        let disabled = await manager.setAllSiteComponentsDisabled(true, onHost: "https://WHOLE.test/path")
        check(disabled && manager.areAllSiteComponentsDisabled(onHost: host), "all components turn off together")
        check(manager.filterDisabledSites.contains(host), "Site Settings sees filtering off")
        check(manager.areUserScriptsDisabled(onHost: host), "Site Settings sees userscripts off")
        check(manager.isZapperDisabled(forHost: host), "zapper off persists without rules")
        check(manager.isAutoplayAllowed(onHost: host), "off allows autoplay")
        _ = await manager.synchronizeZapperRules(forHost: host, rules: [])
        check(manager.areAllSiteComponentsDisabled(onHost: host), "empty browser sync must not re-enable zapper")
        await manager.setZapperRules(forHost: host, rules: [".ad"])
        check(manager.isZapperDisabled(forHost: host), "adding a selector preserves the site choice")
        await manager.deleteAllZapperRules(forHost: host)
        _ = await manager.synchronizeZapperRules(forHost: host, rules: [])
        check(manager.isZapperDisabled(forHost: host), "clearing selectors preserves the site choice")
        _ = await reloaded.refreshFromDiskIfModified(forceRead: true)
        check(reloaded.areAllSiteComponentsDisabled(onHost: host), "all-off state survives a disk reload")
        let enabled = await manager.setAllSiteComponentsDisabled(false, onHost: host)
        check(enabled && !manager.filterDisabledSites.contains(host), "on restores filtering")
        check(!manager.areUserScriptsDisabled(onHost: host) && !manager.isZapperDisabled(forHost: host), "on restores scripts and zapper")
        check(!manager.isAutoplayAllowed(onHost: host), "on restores the autoplay blocker even when globally off")
        check(!manager.isNoAutoplayEnabled, "combined switch does not change global autoplay")
        _ = await manager.setAllSiteComponentsDisabled(true, onHost: "parent.test")
        _ = await manager.setAllSiteComponentsDisabled(false, onHost: "child.parent.test")
        check(!HostMatcher.isHostDisabled(host: "child.parent.test", disabledSites: manager.filterDisabledSites), "on clears inherited filtering exclusions")
        check(!manager.areUserScriptsDisabled(onHost: "child.parent.test"), "on clears inherited userscript exclusions")
        await manager.setWhitelistedDomains(["locked.test"])
        let locked = await manager.setAllSiteComponentsDisabled(false, onHost: "child.locked.test")
        check(!locked && manager.areAllSiteComponentsDisabled(onHost: "child.locked.test"), "master whitelist stays locked")
        let invalid = await manager.setAllSiteComponentsDisabled(true, onHost: "")
        check(!invalid, "invalid host cannot save")
        check(manager.isAutoplayAllowed(onHost: "another.bandcamp.com"), "unrelated settings survive combined edits")
        let failingDirectory = directory.appendingPathComponent("blocked-store")
        let failing = ProtobufDataManager.makeIsolatedForTesting(dataDirectoryURL: failingDirectory)
        _ = await failing.setNoAutoplayEnabled(true)
        try! FileManager.default.removeItem(at: failingDirectory)
        try! Data().write(to: failingDirectory)
        let failedSave = await failing.setAllSiteComponentsDisabled(true, onHost: "failure.test")
        check(!failedSave, "unwritable storage must report failure")
        check(failing.filterDisabledSites.isEmpty && !failing.areUserScriptsDisabled(onHost: "failure.test"), "failed write cannot change filtering or scripts")
        check(!failing.isZapperDisabled(forHost: "failure.test") && !failing.isAutoplayAllowed(onHost: "failure.test"), "failed write cannot change zapper or autoplay")
        print("site component disable policy passed")
    }
}
