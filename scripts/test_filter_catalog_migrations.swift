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
        let defaults = loader.getDefaultFilterLists()
        let replacements = [
            ("EasyList Italy", "https://easylist-downloads.adblockplus.org/easylistitaly.txt", "AdGuard Italian filter"),
            ("Official Polish filters for AdBlock, uBlock Origin & AdGuard", "https://raw.githubusercontent.com/MajkiIT/polish-ads-filter/master/polish-adblock-filters/adblock.txt", "AdGuard Polish filter"),
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
        // wBlock 4: replaced AdGuard lists are removed and hand their selection
        // to the uBO lists; other lists, custom ones included, are untouched.
        let byName = Dictionary(defaults.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for (adGuard, replacements) in FilterListLoader.adGuardReplacements {
            precondition(byName[adGuard] == nil, "\(adGuard) is replaced and must leave the catalog")
            precondition(Set(replacements).isSubset(of: Set(byName.keys)), "unknown list in \(adGuard) handover")
        }
        func adGuard(_ name: String, selected: Bool, custom: Bool = false) -> FilterList {
            FilterList(name: name, url: URL(string: "https://example.com/\(UUID())")!, category: .ads, isCustom: custom, isSelected: selected)
        }
        var base = adGuard("AdGuard Base Filter", selected: true)
        base.updatesAutomatically = false
        base.excludedSites = ["a.com"]
        var tracking = adGuard("AdGuard Tracking Protection Filter", selected: true)
        tracking.excludedSites = ["b.com"]
        var stored = defaults.map { list -> FilterList in var list = list; list.isSelected = false; return list } + [
            base, tracking,
            adGuard("AdGuard Popups", selected: false), adGuard("AdGuard Cookie Notices", selected: true, custom: true),
        ]
        // The user already runs EasyPrivacy with their own settings.
        let easyPrivacy = stored.firstIndex { $0.name == "EasyPrivacy" }!
        stored[easyPrivacy].isSelected = true
        stored[easyPrivacy].excludedSites = ["mine.com"]

        // Offline: no replacement has content, so only the unselected list goes.
        let offline = FilterListLoader.handingOverReplacedAdGuardLists(stored, hasContent: { _ in false })
        precondition(offline.removed.map(\.name) == ["AdGuard Popups"], "offline: \(offline.removed.map(\.name))")
        precondition(offline.lists.contains { $0.name == "AdGuard Base Filter" && $0.isSelected }, "a list keeps protecting until it can hand over")

        // Only Base's replacements arrived: Base hands over, Tracking waits.
        let baseReplacements = Set(FilterListLoader.adGuardReplacements["AdGuard Base Filter"]!)
        let partial = FilterListLoader.handingOverReplacedAdGuardLists(offline.lists, hasContent: { baseReplacements.contains($0.name) })
        precondition(partial.removed.map(\.name) == ["AdGuard Base Filter"], "partial: \(partial.removed.map(\.name))")
        let ads = partial.lists.first { $0.name == "uBlock filters – Ads" }!
        precondition(ads.isSelected && !ads.updatesAutomatically && ads.excludedSites == ["a.com"], "settings move with the selection: \(ads)")

        let done = FilterListLoader.handingOverReplacedAdGuardLists(partial.lists, hasContent: { _ in true })
        precondition(done.removed.map(\.name) == ["AdGuard Tracking Protection Filter"])
        let selected = Set(done.lists.filter(\.isSelected).map(\.name))
        let expected: Set<String> = ["uBlock filters – Ads", "uBlock filters – Badware risks", "uBlock filters – Quick fixes",
                                     "uBlock filters – Unbreak", "EasyList", "Online Malicious URL Blocklist",
                                     "uBlock filters – Privacy", "EasyPrivacy", "AdGuard Cookie Notices"]
        precondition(selected == expected, "handover: \(selected)")
        precondition(done.lists.first { $0.name == "uBlock filters – Privacy" }!.excludedSites == ["b.com"])
        precondition(done.lists.first { $0.name == "EasyPrivacy" }!.excludedSites == ["mine.com"], "a list the user set up keeps its settings")
        precondition(FilterListLoader.handingOverReplacedAdGuardLists(done.lists, hasContent: { _ in true }).removed.isEmpty, "runs once")

        // A default name that matches no catalog entry would silently drop that list from the defaults.
        let catalogNames = Set(defaults.map(\.name))
        for names in [FilterListLoader.recommendedFilterNames, FilterListLoader.minimalFilterNames, FilterListLoader.essentialFilterNames] {
            precondition(names.isSubset(of: catalogNames), "default names missing from catalog: \(names.subtracting(catalogNames))")
        }
        // Lists whose source moved to uBlock Origin's copy keep the selection their users already have.
        let moved = [
            ("https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/118_optimized.txt", "EasyPrivacy"),
            ("https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/204_optimized.txt", "Peter Lowe's Blocklist"),
        ]
        for (oldURL, name) in moved {
            let current = defaults.first { $0.name == name }!
            for selected in [false, true] {
                let old = FilterList(name: name, url: URL(string: oldURL)!, category: .privacy, isSelected: selected)
                let hydrated = FilterListSetup.hydrate(loader.migrateFilterURLs(in: [old]), defaults: defaults)[0]
                precondition(hydrated.url == current.url && hydrated.isSelected == selected, "moved list \(name) lost its URL or selection")
            }
        }
        print("PASS: replacement migrations preserve selection and discard legacy content")
    }
}
