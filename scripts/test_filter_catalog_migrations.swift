import Foundation
import wBlockCoreService

private final class TestLoader: FilterListLoader {
    let container: URL
    init(container: URL) { self.container = container }
    override func getSharedContainerURL() -> URL? { container }
}

@main struct FilterCatalogMigrationTests {
    static func main() throws {
        let fm = FileManager.default
        let container = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: container) }
        let loader = TestLoader(container: container)
        for (url, trusted) in [
            ("https://filters.adtidy.org/extension/chromium/filters/2.txt", true),
            ("https://filters.adtidy.org/extension/ublock/filters/2_without_easylist.txt", true),
            ("https://filters.adtidy.org/extension/ublock/filters/4.txt", true),
            ("https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/17_optimized.txt", true),
            ("https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/BaseFilter/sections/general.txt", true),
            ("https://filters.adtidy.org/extension/chromium/filters/101.txt", false),
            ("https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/118_optimized.txt", false),
        ] {
            let list = FilterList(name: "test", url: URL(string: url)!, category: .ads)
            precondition(list.isTrustedSource == trusted, "incorrect trust for \(url)")
        }
        let defaults = loader.getDefaultFilterLists()
        let replacements = [
            ("Fanboy's Anti-AI Suggestions", "https://raw.githubusercontent.com/easylist/easylist/refs/heads/master/fanboy-addon/fanboy_ai_suggestions.txt", "Stevo's AI Blocklist"),
        ]
        for (oldName, oldURL, newName) in replacements {
            let current = defaults.first { $0.name == newName }!
            for selected in [false, true] {
                var old = FilterList(name: oldName, url: URL(string: oldURL)!, category: .foreign, isSelected: selected)
                old.etag = "old-etag"
                old.serverLastModified = "old-date"
                let migrated = loader.migrateFilterURLs(in: [old])
                let hydrated = FilterListSetup.hydrate(migrated, defaults: defaults)[0]
                precondition(hydrated.url == current.url && hydrated.name == newName)
                precondition(hydrated.id == old.id && hydrated.isSelected == selected)
                precondition(hydrated.etag == nil && hydrated.serverLastModified == nil)
                precondition(loader.migrateFilterURLs(in: [hydrated]) == [hydrated])
                old.isCustom = true
                precondition(loader.migrateFilterURLs(in: [old]) == [old])
            }
            let filename = ContentBlockerIncrementalCache.localFilename(for: current)
            let newURL = container.appendingPathComponent(filename)
            let newBaseline = container.appendingPathComponent("diff-baseline-\(filename)")
            for prefix in ["", "diff-baseline-"] {
                let oldFile = ContentBlockerIncrementalCache.safeLegacyFileURL(name: oldName, containerURL: container, prefix: prefix)!
                try "! Title: \(oldName)\n||old.example^".write(to: oldFile, atomically: true, encoding: .utf8)
            }
            try "! Title: \(oldName)\n||old.example^".write(to: newURL, atomically: true, encoding: .utf8)
            try "old baseline".write(to: newBaseline, atomically: true, encoding: .utf8)
            loader.migrateBuiltInFilterFilesIfNeeded(current)
            precondition(!fm.fileExists(atPath: newURL.path) && !fm.fileExists(atPath: newBaseline.path))
            for prefix in ["", "diff-baseline-"] {
                let oldFile = ContentBlockerIncrementalCache.safeLegacyFileURL(name: oldName, containerURL: container, prefix: prefix)!
                precondition(!fm.fileExists(atPath: oldFile.path), "replaced source must be downloaded, never renamed")
            }
            try "! Title: \(newName)\n||new.example^".write(to: newURL, atomically: true, encoding: .utf8)
            try "new baseline".write(to: newBaseline, atomically: true, encoding: .utf8)
            loader.migrateBuiltInFilterFilesIfNeeded(current)
            precondition(fm.fileExists(atPath: newURL.path) && fm.fileExists(atPath: newBaseline.path))
        }
        // wBlock 4: replaced AdGuard lists stay in the catalog, off for new
        // installs, and hand a wBlock 3 selection to the uBO lists once.
        let byName = Dictionary(defaults.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for (adGuard, replacements) in FilterListLoader.adGuardReplacements {
            precondition(byName[adGuard]?.isSelected == false, "\(adGuard) stays available, off by default")
            precondition(Set(replacements).isSubset(of: Set(byName.keys)), "unknown list in \(adGuard) handover")
        }
        // Regional AdGuard lists whose language uBlock Origin covers with a different list hand over to that list.
        for (adGuard, target) in [
            ("AdGuard German filter", "EasyList Germany"),
            ("AdGuard Italian filter", "EasyList Italy"),
            ("AdGuard Polish filter", "Official Polish filters for AdBlock, uBlock Origin & AdGuard"),
            ("AdGuard Russian filter", "RU AdList"),
        ] {
            precondition(FilterListLoader.adGuardReplacements[adGuard] == [target], "\(adGuard) must hand over to \(target)")
            precondition(byName[target] != nil, "\(target) must be in the catalog")
        }
        // A catalog URL that is also a migration source would reset its validators on every launch.
        for list in defaults {
            var probe = list
            probe.etag = "kept"
            precondition(loader.migrateFilterURLs(in: [probe])[0].etag == "kept", "\(list.name) is migrated away from its own URL")
        }
        func adGuard(_ name: String, selected: Bool, custom: Bool = false) -> FilterList {
            FilterList(name: name, url: URL(string: "https://example.com/\(UUID())")!, category: .ads, isCustom: custom, isSelected: selected)
        }
        var base = adGuard("AdGuard Base Filter", selected: true)
        base.updatesAutomatically = false
        base.excludedSites = ["a.com"]
        var tracking = adGuard("AdGuard Tracking Protection Filter", selected: true)
        tracking.excludedSites = ["b.com"]
        let popups = adGuard("AdGuard Popups", selected: true)
        var stored = defaults.map { list -> FilterList in var list = list; list.isSelected = false; return list } + [
            base, tracking, popups, adGuard("AdGuard Cookie Notices", selected: true, custom: true),
        ]
        // The user already runs EasyPrivacy with their own settings.
        let easyPrivacy = stored.firstIndex { $0.name == "EasyPrivacy" }!
        stored[easyPrivacy].isSelected = true
        stored[easyPrivacy].excludedSites = ["mine.com"]
        // Popups was on at upgrade but the user turned it off before it handed over.
        stored[stored.firstIndex { $0.id == popups.id }!].isSelected = false
        let pending: Set<UUID> = [base.id, tracking.id, popups.id]

        // Offline: no replacement has content, so nothing hands over yet.
        let offline = FilterListLoader.handingOverReplacedAdGuardLists(stored, pending: pending, hasContent: { _ in false })
        precondition(offline.handedOver.isEmpty, "offline: \(offline.handedOver.map(\.name))")
        precondition(offline.settled == [popups.id], "a list turned off leaves the handover: \(offline.settled)")
        precondition(offline.lists.contains { $0.id == base.id && $0.isSelected }, "a list keeps protecting until it can hand over")
        // Nothing pending (fresh install, 4.x, or a list turned on after the upgrade): AdGuard lists stay on.
        let optIn = FilterListLoader.handingOverReplacedAdGuardLists(stored, pending: [], hasContent: { _ in true })
        precondition(optIn.handedOver.isEmpty && optIn.lists == stored, "an AdGuard list turned on in wBlock 4 stays on")

        var urlTracking = adGuard("AdGuard URL Tracking Protection Filter", selected: true)
        urlTracking.excludedSites = ["url.example"]
        let overlap = defaults.map { list -> FilterList in var list = list; list.isSelected = false; return list } + [tracking, urlTracking]
        let overlapPending: Set<UUID> = [tracking.id, urlTracking.id]
        let first = FilterListLoader.handingOverReplacedAdGuardLists(overlap, pending: overlapPending, hasContent: { $0.name == "uBlock filters – Privacy" })
        let second = FilterListLoader.handingOverReplacedAdGuardLists(first.lists, pending: overlapPending.subtracting(first.settled), hasContent: { _ in true })
        precondition(second.lists.first { $0.name == "uBlock filters – Privacy" }!.excludedSites == ["b.com", "url.example"], "overlapping handovers must combine settings regardless of download order")

        // Only Base's replacements arrived: Base hands over, Tracking waits.
        let baseReplacements = Set(FilterListLoader.adGuardReplacements["AdGuard Base Filter"]!)
        let remaining = pending.subtracting(offline.settled)
        let partial = FilterListLoader.handingOverReplacedAdGuardLists(offline.lists, pending: remaining, hasContent: { baseReplacements.contains($0.name) })
        precondition(partial.handedOver.map(\.name) == ["AdGuard Base Filter"], "partial: \(partial.handedOver.map(\.name))")
        precondition(partial.lists.contains { $0.id == base.id && !$0.isSelected }, "a handed-over list is turned off, not removed")
        let ads = partial.lists.first { $0.name == "uBlock filters – Ads" }!
        precondition(ads.isSelected && !ads.updatesAutomatically && ads.excludedSites == ["a.com"], "settings move with the selection: \(ads)")

        let done = FilterListLoader.handingOverReplacedAdGuardLists(partial.lists, pending: remaining.subtracting(partial.settled), hasContent: { _ in true })
        precondition(done.handedOver.map(\.name) == ["AdGuard Tracking Protection Filter"])
        precondition(remaining.subtracting(partial.settled).subtracting(done.settled).isEmpty, "the handover finishes")
        let selected = Set(done.lists.filter(\.isSelected).map(\.name))
        let expected: Set<String> = ["uBlock filters – Ads", "uBlock filters – Badware risks", "uBlock filters – Quick fixes",
                                     "uBlock filters – Unbreak", "EasyList", "Online Malicious URL Blocklist",
                                     "uBlock filters – Privacy", "EasyPrivacy", "AdGuard Cookie Notices"]
        precondition(selected == expected, "handover: \(selected)")
        precondition(done.lists.first { $0.name == "uBlock filters – Privacy" }!.excludedSites == ["b.com"])
        precondition(done.lists.first { $0.name == "EasyPrivacy" }!.excludedSites == ["mine.com"], "a list the user set up keeps its settings")
        // Turned on again after the handover: nothing is pending, so it stays on.
        var reenabled = done.lists
        reenabled[reenabled.firstIndex { $0.id == base.id }!].isSelected = true
        precondition(FilterListLoader.handingOverReplacedAdGuardLists(reenabled, pending: [], hasContent: { _ in true }).lists == reenabled,
                     "an AdGuard list turned back on stays on")

        // A default name that matches no catalog entry would silently drop that list from the defaults.
        let catalogNames = Set(defaults.map(\.name))
        for names in [FilterListLoader.recommendedFilterNames, FilterListLoader.minimalFilterNames, FilterListLoader.essentialFilterNames] {
            precondition(names.isSubset(of: catalogNames), "default names missing from catalog: \(names.subtracting(catalogNames))")
        }
        // Lists whose source moved to uBlock Origin's copy, or that were renamed, keep their users' selection.
        let registry = "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms"
        let moved = [
            ("\(registry)/extension/safari/filters/118_optimized.txt", "EasyPrivacy", "EasyPrivacy"),
            ("\(registry)/extension/safari/filters/204_optimized.txt", "Peter Lowe's Blocklist", "Peter Lowe's Blocklist"),
            // Regional lists that now come from uBlock Origin's sources: the AdGuard copy and the old upstream URL.
            ("\(registry)/extension/safari/filters/112_optimized.txt", "Liste AR", "Liste AR"),
            ("https://adblock.ee/list.txt", "Estonian List", "Estonian List"),
            ("\(registry)/extension/safari/filters/258_optimized.txt", "Block Outsider Intrusion into LAN", "Block Outsider Intrusion into LAN"),
            ("\(registry)/extension/safari/filters/123_optimized.txt", "Fanboy's Social Blocking List", "EasyList – Social Widgets"),
            ("https://easylist.to/easylist/fanboy-social.txt", "Fanboy's Social Blocking List", "EasyList – Social Widgets"),
            ("\(registry)/extension/safari/filters/2_optimized.txt", "AdGuard Base Filter", "AdGuard Base Filter"),
            ("\(registry)/extension/safari/filters/4_optimized.txt", "AdGuard Social Media Filter", "AdGuard Social Media Filter"),
            ("\(registry)/ios/filters/11_optimized.txt", "AdGuard Mobile Filter", "AdGuard Mobile Filter"),
            ("\(registry)/mac_v3/filters/17_optimized.txt", "AdGuard URL Tracking Protection Filter", "AdGuard URL Tracking Protection Filter"),
            ("\(registry)/extension/safari/filters/25.txt", "AdGuard Mail Tracking Protection Filter", "AdGuard Mail Tracking Protection Filter"),
            ("https://ublockorigin.github.io/uAssetsCDN/thirdparties/easylist-annoyances.txt", "EasyList – Annoyances", "EasyList – Other Annoyances"),
            ("\(registry)/mac_v3/filters/251_optimized.txt", "Actually Legitimate URL Shortener Tool", "Actually Legitimate URL Shortener Tool"),
            ("\(registry)/extension/safari/filters/259_optimized.txt", "Dandelion Sprout's Anti-Malware List", "Dandelion Sprout's Anti-Malware List"),
            ("\(registry)/extension/safari/filters/120_optimized.txt", "AdBlockID", "AdBlockID"),
            ("\(registry)/extension/safari/filters/232_optimized.txt", "KAD - Anti-Scam", "KAD - Anti-Scam"),
            // Persian Blocker's entry merged into PersianBlockerNG, which is the same project's list at uBlock Origin's address.
            ("\(registry)/extension/safari/filters/235_optimized.txt", "Persian Blocker", "PersianBlockerNG"),
        ]
        for (oldURL, oldName, name) in moved {
            let current = defaults.first { $0.name == name }!
            for selected in [false, true] {
                let old = FilterList(name: oldName, url: URL(string: oldURL)!, category: .privacy, isSelected: selected)
                let hydrated = FilterListSetup.hydrate(loader.migrateFilterURLs(in: [old]), defaults: defaults)[0]
                precondition(hydrated.url == current.url && hydrated.name == name && hydrated.isSelected == selected,
                             "moved list \(name) lost its URL, name, or selection")
            }
        }
        // A renamed list keeps its cached copy under the new name. A list whose source moved drops the old copy.
        let annoyances = defaults.first { $0.name == "EasyList – Other Annoyances" }!
        let annoyancesOld = container.appendingPathComponent("EasyList – Annoyances.txt")
        try "! Title: EasyList – Annoyances\n||old.example^".write(to: annoyancesOld, atomically: true, encoding: .utf8)
        loader.migrateBuiltInFilterFilesIfNeeded(annoyances)
        precondition(fm.fileExists(atPath: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: annoyances)).path)
                     && !fm.fileExists(atPath: annoyancesOld.path), "renamed cache was not carried over")
        // Persian Blocker's cached copy came from another source, so PersianBlockerNG downloads its own.
        let persian = defaults.first { $0.name == "PersianBlockerNG" }!
        let persianOld = container.appendingPathComponent("Persian Blocker.txt")
        try "! Title: Persian Blocker (Optimized)\n||old.example^".write(to: persianOld, atomically: true, encoding: .utf8)
        loader.migrateBuiltInFilterFilesIfNeeded(persian)
        precondition(!fm.fileExists(atPath: persianOld.path)
                     && !fm.fileExists(atPath: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: persian)).path),
                     "a Persian Blocker copy from another source must not carry over")
        // Moved lists on raw GitHub keep a jsDelivr fallback, derived from the same address.
        for name in ["Actually Legitimate URL Shortener Tool", "Dandelion Sprout's Anti-Malware List", "AdBlockID", "KAD - Anti-Scam"] {
            let url = defaults.first { $0.name == name }!.url
            precondition(FilterListURLMirror.fallbackURLs(for: url).contains { $0.host == "cdn.jsdelivr.net" }, "\(name) has no jsDelivr fallback")
        }
        let social = defaults.first { $0.name == "EasyList – Social Widgets" }!
        let socialOld = container.appendingPathComponent("Fanboy's Social Blocking List.txt")
        try "! Title: Fanboy's Social Blocking List\n||old.example^".write(to: socialOld, atomically: true, encoding: .utf8)
        loader.migrateBuiltInFilterFilesIfNeeded(social)
        precondition(!fm.fileExists(atPath: socialOld.path)
                     && !fm.fileExists(atPath: container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: social)).path),
                     "a list whose source moved must not carry its old copy")

        // Every registry address of a kept AdGuard list moves to uBlock Origin's copy, which the catalog uses.
        let catalogURLs = Set(defaults.map(\.url))
        for id in [1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 13, 16, 17, 18, 19, 20, 21, 22, 23, 25, 26, 27, 224] {
            let migrated = FilterListLoader.migratedURL(for: "\(registry)/extension/safari/filters/\(id)_optimized.txt")
            precondition(migrated.map(catalogURLs.contains) == true, "AdGuard \(id) does not migrate to a catalog URL")
        }
        for list in defaults where list.name.hasPrefix("AdGuard ") {
            precondition(list.url.host == "filters.adtidy.org" && list.url.path.contains("/extension/ublock/filters/"),
                         "\(list.name) should load uBlock Origin's copy")
        }
        // Lists added from the old registry browser are custom: their address and name stay as the user saved them.
        let registryCustom = FilterList(name: "AdGuard Social Media Filter", url: URL(string: "\(registry)/extension/safari/filters/4_optimized.txt")!,
                                        category: .annoyances, isCustom: true, isSelected: true)
        precondition(loader.migrateFilterURLs(in: [registryCustom])[0].url == registryCustom.url, "custom registry list was migrated")
        precondition(FilterListSetup.hydrate([registryCustom], defaults: defaults)[0].name == registryCustom.name, "custom registry list was renamed")

        // Retired built-ins leave the catalog and are recognized by address, so they go without errors.
        let retired = [
            ("\(registry)/extension/safari/filters/207_optimized.txt", "Adblock Warning Removal List"),
            ("\(registry)/extension/safari/filters/10_optimized.txt", "AdGuard Allowlist"),
            ("\(registry)/extension/safari/filters/10.txt", "AdGuard Allowlist"),
            ("https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/whitelist-referral.txt", "HaGeZi Referral Allowlist"),
        ]
        for (url, name) in retired {
            precondition(!defaults.contains { $0.name == name }, "\(name) is still in the catalog")
            for selected in [false, true] {
                let filter = FilterList(name: name, url: URL(string: url)!, category: .annoyances, isSelected: selected)
                precondition(FilterListLoader.isRetiredBuiltIn(filter), "\(name) is not retired")
            }
            let custom = FilterList(name: name, url: URL(string: url)!, category: .custom, isCustom: true, isSelected: true)
            precondition(!FilterListLoader.isRetiredBuiltIn(custom), "a custom copy of \(name) must stay")
        }

        // Quick fixes and Unbreak moved to Ads. A user's stored copy takes the catalog category and keeps its selection.
        for name in ["uBlock filters – Quick fixes", "uBlock filters – Unbreak"] {
            let storedList = FilterList(name: name, url: defaults.first { $0.name == name }!.url, category: .custom, isSelected: true)
            let hydrated = FilterListSetup.hydrate([storedList], defaults: defaults)[0]
            precondition(hydrated.category == .ads && hydrated.isSelected, "\(name) did not move to Ads")
        }
        precondition(!defaults.contains { $0.name.contains("AI Widgets") }, "EasyList AI Widgets must not be added")
        // New lists are off by default, and EasyDutch sits with the other regional lists.
        for name in ["EasyList – Chat Widgets", "EasyList – Newsletter Notices", "EasyList – Notifications", "EasyDutch",
                     "uBlock filters – Experimental", "Phishing URL Blocklist", "Fanboy – Anti-Facebook", "Dan Pollock's hosts file"] {
            precondition(byName[name]?.isSelected == false, "\(name) must default to off")
        }
        precondition(byName["EasyDutch"]?.category == .foreign && byName["EasyList – Chat Widgets"]?.category == .annoyances)
        precondition(byName["uBlock filters – Experimental"]?.category == .experimental && byName["Phishing URL Blocklist"]?.category == .security
                     && byName["Dan Pollock's hosts file"]?.category == .multipurpose && byName["Fanboy – Anti-Facebook"]?.category == .annoyances)
        print("PASS: replacement migrations preserve selection and discard legacy content")
    }
}
