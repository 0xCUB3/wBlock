//
//  FilterListLoader.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import Foundation
import wBlockCoreService

class FilterListLoader {
    // Defaults mirror uBlock Origin's default-enabled lists, plus wBlock's own hosts list.
    static let minimalFilterNames: Set<String> = ["uBlock filters – Ads", "EasyList"]
    static let recommendedFilterNames: Set<String> = [
        "uBlock filters – Ads",
        "uBlock filters – Privacy",
        "uBlock filters – Badware risks",
        "uBlock filters – Quick fixes",
        "uBlock filters – Unbreak",
        "EasyList",
        "EasyPrivacy",
        "Peter Lowe's Blocklist",
        "Online Malicious URL Blocklist",
        "Actually Legitimate URL Shortener Tool",
        "wBlock Ad and Tracking Hosts",
    ]

    // Lists that prompt an "essential protection" warning before they are disabled.
    // Compatibility fixes and the hosts list are convenience, not protection.
    static let essentialFilterNames: Set<String> = recommendedFilterNames.subtracting([
        "uBlock filters – Quick fixes", "uBlock filters – Unbreak", "wBlock Ad and Tracking Hosts",
    ])

    /// wBlock 4 replaced these AdGuard lists with uBlock Origin's. Each one
    /// hands its selection to the lists it maps to.
    static let adGuardReplacements: [String: [String]] = {
        let ads = ["uBlock filters – Ads", "uBlock filters – Badware risks", "uBlock filters – Quick fixes",
                   "uBlock filters – Unbreak", "EasyList", "Online Malicious URL Blocklist"]
        let annoyances = ["uBlock filters – Annoyances", "EasyList – Annoyances"]
        return [
            "AdGuard Base Filter": ads,
            "AdGuard Mobile Filter": ads,
            "AdGuard Tracking Protection Filter": ["uBlock filters – Privacy", "EasyPrivacy"],
            "AdGuard URL Tracking Protection Filter": ["uBlock filters – Privacy"],
            "AdGuard Cookie Notices": ["uBlock filters – Cookie Notices", "EasyList – Cookie Notices"],
            "AdGuard German filter": ["EasyList Germany"],
            "AdGuard Italian filter": ["EasyList Italy"],
            "AdGuard Polish filter": ["Official Polish filters for AdBlock, uBlock Origin & AdGuard"],
            "AdGuard Russian filter": ["RU AdList"],
            "AdGuard Popups": annoyances,
            "AdGuard Other Annoyances": annoyances,
            "AdGuard Mobile App Banners": annoyances,
            "AdGuard Widgets": annoyances,
        ]
    }()

    static func isReplacedAdGuardList(_ list: FilterList) -> Bool {
        !list.isCustom && adGuardReplacements[list.name] != nil
    }

    /// Retires the built-in AdGuard lists that uBO lists replaced. An unselected
    /// one is simply removed. A selected one hands over only once every
    /// replacement `hasContent`, so it keeps protecting (offline, say) until
    /// then. Its replacements are turned on and, unless the user had already
    /// turned one on, inherit its settings: automatic updates stay off if any
    /// predecessor had them off, excluded sites are combined, and site-only
    /// scoping is kept only when every predecessor used it.
    static func handingOverReplacedAdGuardLists(
        _ lists: [FilterList], hasContent: (FilterList) -> Bool
    ) -> (lists: [FilterList], removed: [FilterList]) {
        let byName = Dictionary(lists.filter { !$0.isCustom }.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        let pending = lists.filter(isReplacedAdGuardList)
        var ready = pending.filter { list in
            !list.isSelected || (adGuardReplacements[list.name] ?? []).allSatisfy { byName[$0].map(hasContent) == true }
        }
        while true {
            let readyIDs = Set(ready.map(\.id))
            let blockedNames = Set(pending.filter { $0.isSelected && !readyIDs.contains($0.id) }
                .flatMap { adGuardReplacements[$0.name] ?? [] })
            let next = ready.filter { !$0.isSelected || blockedNames.isDisjoint(with: adGuardReplacements[$0.name] ?? []) }
            if next.count == ready.count { break }
            ready = next
        }
        guard !ready.isEmpty else { return (lists, []) }
        var predecessors: [String: [FilterList]] = [:]
        for list in ready where list.isSelected {
            for name in adGuardReplacements[list.name] ?? [] { predecessors[name, default: []].append(list) }
        }
        let retired = Set(ready.map(\.id))
        let kept = lists.filter { !retired.contains($0.id) }.map { list -> FilterList in
            guard !list.isCustom, let from = predecessors[list.name] else { return list }
            var list = list
            if !list.isSelected {
                list.updatesAutomatically = from.allSatisfy(\.updatesAutomatically)
                list.excludedSites = Array(Set(from.flatMap(\.excludedSites))).sorted()
                list.onlySelectedSites = from.allSatisfy(\.onlySelectedSites)
                list.selectedSites = list.onlySelectedSites ? Array(Set(from.flatMap(\.selectedSites))).sorted() : []
            }
            list.isSelected = true
            return list
        }
        return (kept, ready)
    }

    /// Was built into wBlock 5 while any list was on, so upgrades turn it on
    /// whenever another list is on (#994).
    static let adTrackingHostsURL = URL(
        string: "https://raw.githubusercontent.com/0xCUB3/wBlock/main/filters/ad-tracking-hosts.txt"
    )!

    private static let stevoAIBlocklistURL = URL(
        string: "https://raw.githubusercontent.com/Stevoisiak/Stevos-AI-Blocklist/refs/heads/main/GenAI-Blocklist.txt"
    )!

    private static func registryURL(_ id: Int) -> String {
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/\(id)_optimized.txt"
    }

    private static func registryRefsURL(_ id: Int) -> String {
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/\(id)_optimized.txt"
    }

    /// uBlock Origin's build of an AdGuard list. wBlock 4 uses it in place of the registry copy.
    private static func adGuardUBlockURL(_ id: Int) -> URL {
        URL(string: "https://filters.adtidy.org/extension/ublock/filters/\(id).txt")!
    }

    private static let filterURLMigrations: [String: URL] = [
        // EasyPrivacy and Peter Lowe's Blocklist now come from uBlock Origin's sources.
        registryURL(118):
            URL(string: "https://cdn.jsdelivr.net/gh/uBlockOrigin/uAssetsCDN@main/thirdparties/easyprivacy.txt")!,
        registryURL(204):
            URL(string: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=1&mimetype=plaintext")!,
        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/LegitimateURLShortener.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/mac_v3/filters/251_optimized.txt")!,
        "https://raw.githubusercontent.com/realodix/AdBlockID/main/dist/adblockid.adfl.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/120_optimized.txt")!,
        // Same-list switches: the AdGuard builds and the upstream URLs they came from move to uBlock Origin's copy.
        registryRefsURL(224): adGuardUBlockURL(224),
        registryURL(224): adGuardUBlockURL(224),
        registryRefsURL(16): adGuardUBlockURL(16),
        registryURL(16): adGuardUBlockURL(16),
        registryRefsURL(8): adGuardUBlockURL(8),
        registryURL(8): adGuardUBlockURL(8),
        registryRefsURL(7): adGuardUBlockURL(7),
        registryURL(7): adGuardUBlockURL(7),
        registryRefsURL(9): adGuardUBlockURL(9),
        registryURL(9): adGuardUBlockURL(9),
        registryRefsURL(13): adGuardUBlockURL(13),
        registryURL(13): adGuardUBlockURL(13),
        registryRefsURL(23): adGuardUBlockURL(23),
        registryURL(23): adGuardUBlockURL(23),
        registryURL(102):
            URL(string: "https://raw.githubusercontent.com/ABPindo/indonesianadblockrules/master/subscriptions/abpindo.txt")!,
        registryURL(103): URL(string: "https://stanev.org/abp/adblock_bg.txt")!,
        registryURL(105):
            URL(string: "https://raw.githubusercontent.com/tomasko126/easylistczechandslovak/master/filters.txt")!,
        registryURL(108):
            URL(string: "https://raw.githubusercontent.com/easylist/EasyListHebrew/master/EasyListHebrew.txt")!,
        registryURL(110):
            URL(string: "https://cdn.jsdelivr.net/gh/EasyList-Lithuania/easylist_lithuania@master/easylistlithuania.txt")!,
        registryURL(111):
            URL(string: "https://raw.githubusercontent.com/Latvian-List/adblock-latvian/master/lists/latvian-list.txt")!,
        registryURL(112): URL(string: "https://easylist-downloads.adblockplus.org/Liste_AR.txt")!,
        registryURL(119): URL(string: "https://raw.githubusercontent.com/brave/adblock-lists/master/custom/is.txt")!,
        registryURL(121): URL(string: "https://www.void.gr/kargig/void-gr-filters.txt")!,
        registryURL(202):
            URL(string: "https://raw.githubusercontent.com/easylist-thailand/easylist-thailand/master/subscription/easylist-thailand.txt")!,
        registryURL(203): URL(string: "https://cdn.jsdelivr.net/gh/hufilter/hufilter@gh-pages/hufilter-ublock.txt")!,
        registryURL(214): URL(string: "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn_ublock.txt")!,
        registryURL(218): URL(string: "https://ubo-et.lepik.io/list.txt")!,
        registryURL(227):
            URL(string: "https://cdn.jsdelivr.net/npm/@filteringdev/filterslists-ko@latest/dist/filterslist-uBlockOrigin-classic.txt")!,
        registryURL(233):
            URL(string: "https://raw.githubusercontent.com/finnish-easylist-addition/finnish-easylist-addition/gh-pages/Finland_adb.txt")!,
        registryURL(236):
            URL(string: "https://raw.githubusercontent.com/tcptomato/ROad-Block/master/road-block-filters-light.txt")!,
        registryURL(243):
            URL(string: "https://raw.githubusercontent.com/lassekongo83/Frellwits-filter-lists/swefilter/swefilter.min.txt")!,
        registryURL(249): URL(string: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianList.txt")!,
        registryURL(252):
            URL(string: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/SerboCroatianList.txt")!,
        registryURL(253): URL(string: "https://easylist-downloads.adblockplus.org/indianlist.txt")!,
        registryURL(254):
            URL(string: "https://raw.githubusercontent.com/DeepSpaceHarbor/Macedonian-adBlock-Filters/master/Filters")!,
        "https://raw.githubusercontent.com/FiltersHeroes/KAD/master/KAD.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/232_optimized.txt")!,
        "https://raw.githubusercontent.com/EasyList-Lithuania/easylist_lithuania/master/easylistlithuania.txt":
            URL(string: "https://cdn.jsdelivr.net/gh/EasyList-Lithuania/easylist_lithuania@master/easylistlithuania.txt")!,
        "https://adblock.ee/list.txt": URL(string: "https://ubo-et.lepik.io/list.txt")!,
        "https://adblock.gardar.net/is.abp.txt": URL(string: "https://raw.githubusercontent.com/brave/adblock-lists/master/custom/is.txt")!,
        "https://cdn.jsdelivr.net/gh/hufilter/hufilter@gh-pages/hufilter-adguard.txt":
            URL(string: "https://cdn.jsdelivr.net/gh/hufilter/hufilter@gh-pages/hufilter-ublock.txt")!,
        "https://raw.githubusercontent.com/lassekongo83/Frellwits-filter-lists/master/Frellwits-Swedish-Filter.txt":
            URL(string: "https://raw.githubusercontent.com/lassekongo83/Frellwits-filter-lists/swefilter/swefilter.min.txt")!,
        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianExperimentalList%20alternate%20versions/NordicFiltersAdGuard.txt":
            URL(string: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianList.txt")!,
        "https://raw.githubusercontent.com/RandomAdversary/Macedonian-adBlock-Filters/master/Filters":
            URL(string: "https://raw.githubusercontent.com/DeepSpaceHarbor/Macedonian-adBlock-Filters/master/Filters")!,
        "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn_adguard.txt":
            URL(string: "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn_ublock.txt")!,
        "https://raw.githubusercontent.com/List-KR/List-KR/refs/heads/master/filter-AdGuard-forward.txt":
            URL(string: "https://cdn.jsdelivr.net/npm/@filteringdev/filterslists-ko@latest/dist/filterslist-uBlockOrigin-classic.txt")!,
        "https://raw.githubusercontent.com/List-KR/List-KR/master/filter-AdGuard-forward.txt": URL(
            string: "https://cdn.jsdelivr.net/npm/@filteringdev/filterslists-ko@latest/dist/filterslist-uBlockOrigin-classic.txt")!,
        "https://filters.adtidy.org/extension/safari/filters/227_optimized.txt":
            URL(string: "https://cdn.jsdelivr.net/npm/@filteringdev/filterslists-ko@latest/dist/filterslist-uBlockOrigin-classic.txt")!,
        "https://raw.githubusercontent.com/easylist/easylist/refs/heads/master/fanboy-addon/fanboy_ai_suggestions.txt": stevoAIBlocklistURL,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/260.txt": stevoAIBlocklistURL,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/260_optimized.txt": stevoAIBlocklistURL,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/25.txt": URL(
            string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/25_optimized.txt")!,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/10.txt": URL(
            string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/10_optimized.txt")!,
        // 2026-09: the worker now mirrors BPC into R2; reads go to the bucket so
        // update checks stop counting against the worker's daily quota.
        "https://bpc-filter-proxy.wmailrelayb8d890.workers.dev": URL(string: "https://pub-d303b9085c0b41b5aa749fc74609d4d9.r2.dev/bpc-paywall-filter.txt")!,
        "https://bpc-filter-proxy.wmailrelayb8d890.workers.dev/": URL(string: "https://pub-d303b9085c0b41b5aa749fc74609d4d9.r2.dev/bpc-paywall-filter.txt")!,
    ]

    /// Legacy names whose list came from a different source than the current
    /// entry, with the header title that identifies that old content. Their
    /// cache must not be carried over under the new name, and a cache already
    /// carried over by an earlier release is dropped so the new source is fetched.
    private static let replacedSourceLegacyTitles: [String: String] = [
        "Fanboy's Anti-AI Suggestions": "! Title: Fanboy's Anti-AI"
    ]

    /// Built-in lists removed from the catalog, matched by URL fragment.
    private static let retiredBuiltInURLFragments = [
        "d3ward/toolz",
        "platforms/extension/safari/filters/208_optimized.txt",  // Online Malicious URL Blocklist (#864)
        "platforms/extension/safari/filters/122_optimized.txt",  // Fanboy's Annoyances Filter (#877)
        "raw.githubusercontent.com/cjx82630/cjxlist/master/cjx-annoyance.txt",  // CJX's Annoyances List (#882)
        "raw.githubusercontent.com/easylist/easylistchina/master/easylistchina.txt",  // EasyList China (#882)
        "easylist-downloads.adblockplus.org/easylistdutch.txt",  // EasyList Dutch (#882)
        "easylist-downloads.adblockplus.org/easylistpolish.txt",  // EasyList Polish (#882)
        "easylist-downloads.adblockplus.org/easylistportuguese.txt",  // EasyList Portuguese (#882)
        "easylist-downloads.adblockplus.org/global-filters.txt",  // Global Filters (#882)
        "easylist-downloads.adblockplus.org/liste_fr.txt",  // Liste FR (#882)
        "raw.githubusercontent.com/PolishFiltersTeam/PolishAnnoyanceFilters/master/PPB.txt",  // Polish Annoyances Filters (#882)
        "raw.githubusercontent.com/olegwukr/polish-privacy-filters/master/anti-adblock.txt",  // Polish Anti Adblock Filters (#882)
        "raw.githubusercontent.com/FiltersHeroes/PolishAntiAnnoyingSpecialSupplement/master/polish_rss_filters.txt",  // Polish Anti-Annoying Special Supplement (#882)
        "raw.githubusercontent.com/MajkiIT/polish-ads-filter/master/cookies_filters/adblock_cookies.txt",  // Polish GDPR-Cookies Filters (#882)
        "raw.githubusercontent.com/MajkiIT/polish-ads-filter/master/adblock_social_filters/adblock_social_list.txt",  // Polish Social Filters (#882)
        "www.zoso.ro/pages/rolist.txt",  // ROList (#882)
        "www.zoso.ro/pages/rolist2.txt",  // ROLIST2 (#882)
        "easylist-downloads.adblockplus.org/advblock.txt",  // RU AdList (#882)
        "easylist-downloads.adblockplus.org/cntblock.txt",  // RU AdList: Counters (#882)
        "raw.githubusercontent.com/gioxx/xfiles/master/filtri.txt",  // Xfiles (#882)
        "raw.githubusercontent.com/xinggsf/Adblock-Plus-Rule/master/rule.txt",  // xinggsf (#882)
        "raw.githubusercontent.com/yous/YousList/master/youslist.txt",  // YousList (#882)
        "raw.githubusercontent.com/MasterKia/PersianBlocker/main/PersianBlocker.txt",  // Persian Blocker, maintainer passed away (#921)
        "raw.githubusercontent.com/AnXh3L0/blocklist/master/albanian-easylist-addition/Albania.txt",  // Adblock List for Albania and Kosovo, unmaintained (#921)
        "raw.githubusercontent.com/lonum1rus/Raajje-AdList/master/filter.txt",  // Raajje AdList, unmaintained (#921)
        "raw.githubusercontent.com/betterwebleon/slovenian-list/master/filters.txt",  // Slovenian List, unmaintained since 2024 (#931)
    ]

    static func isRetiredBuiltIn(_ filter: FilterList) -> Bool {
        !filter.isCustom && (filter.name == "d3Host List by d3ward" || isRetiredBuiltInURL(filter.url))
    }

    static func isRetiredBuiltInURL(_ url: URL) -> Bool {
        retiredBuiltInURLFragments.contains { url.absoluteString.contains($0) }
    }

    /// New built-in names and the names used by the previous catalog release.
    private static let filterNameMigrations: [String: [String]] = [
        "Adblock Warning Removal List": ["Anti-Adblock List"],
        "Stevo's AI Blocklist": ["Fanboy's Anti-AI Suggestions"],
        "HaGeZi Multi Pro Mini": ["HaGeZi Pro Mini", "Hagezi Pro Mini"],
        "filterslists-KO": ["List-KR"],
    ]

    func localFileURL(for filter: FilterList) -> URL? {
        guard let containerURL = getSharedContainerURL() else { return nil }
        return containerURL.appendingPathComponent(
            ContentBlockerIncrementalCache.localFilename(for: filter)
        )
    }

    /// Renames cached built-in content and delta baselines before catalog metadata is hydrated.
    func migrateBuiltInFilterFilesIfNeeded(_ filter: FilterList) {
        guard !filter.isCustom,
              let oldNames = Self.filterNameMigrations[filter.name],
              let containerURL = getSharedContainerURL()
        else { return }

        let localFilename = ContentBlockerIncrementalCache.localFilename(for: filter)
        let newLocalURL = containerURL.appendingPathComponent(localFilename)
        let newBaselineURL = containerURL.appendingPathComponent("diff-baseline-\(localFilename)")
        for oldName in oldNames {
            let replacedSource = Self.replacedSourceLegacyTitles[oldName] != nil
            if let legacyTitle = Self.replacedSourceLegacyTitles[oldName],
               let handle = try? FileHandle(forReadingFrom: newLocalURL) {
                let header = String(decoding: handle.readData(ofLength: 1024), as: UTF8.self)
                try? handle.close()
                if header.contains(legacyTitle) {
                    try? FileManager.default.removeItem(at: newLocalURL)
                    try? FileManager.default.removeItem(at: newBaselineURL)
                }
            }
            if let oldURL = ContentBlockerIncrementalCache.safeLegacyFileURL(
                name: oldName,
                containerURL: containerURL
            ) {
                Self.migrateFileIfNeeded(from: oldURL, to: replacedSource ? nil : newLocalURL)
            }
            if let oldBaselineURL = ContentBlockerIncrementalCache.safeLegacyFileURL(
                name: oldName,
                containerURL: containerURL,
                prefix: "diff-baseline-"
            ) {
                Self.migrateFileIfNeeded(from: oldBaselineURL, to: replacedSource ? nil : newBaselineURL)
            }
        }
    }

    /// Moves a legacy cache file into place, or deletes it when `newURL` is nil.
    static func migrateFileIfNeeded(from oldURL: URL, to newURL: URL?) {
        guard FileManager.default.fileExists(atPath: oldURL.path) else { return }
        guard let newURL else {
            try? FileManager.default.removeItem(at: oldURL)
            return
        }
        guard !FileManager.default.fileExists(atPath: newURL.path) else { return }
        try? FileManager.default.moveItem(at: oldURL, to: newURL)
    }

    static func canonicalFilterURLString(_ urlString: String) -> String {
        filterURLMigrations[urlString]?.absoluteString ?? urlString
    }

    /// Updates known legacy built-in filter URLs; custom lists keep the URL the user added.
    func migrateFilterURLs(in filters: [FilterList]) -> [FilterList] {
        filters.map { filter in
            guard !filter.isCustom, let newURL = Self.filterURLMigrations[filter.url.absoluteString] else {
                return filter
            }

            var migratedFilter = filter
            migratedFilter.url = newURL
            migratedFilter.etag = nil
            migratedFilter.serverLastModified = nil
            return migratedFilter
        }
    }

    /// Returns the default filter lists without any user customizations
    func getDefaultFilterLists() -> [FilterList] {
        return createDefaultFilterLists()
    }

    /// Creates the default set of filter lists
    private func createDefaultFilterLists() -> [FilterList] {
        var filterLists = [
            FilterList(
                id: UUID(), name: "uBlock filters – Ads",
                url: URL(string: "https://ublockorigin.github.io/uAssetsCDN/filters/filters.min.txt")!,
                category: FilterListCategory.ads,
                description: "Ad blocking rules from the uBlock Origin project. Meant to be used alongside EasyList.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "uBlock filters – Privacy",
                url: URL(string: "https://ublockorigin.github.io/uAssetsCDN/filters/privacy.min.txt")!,
                category: FilterListCategory.privacy,
                description: "Blocks trackers and removes tracking parameters from URLs, from the uBlock Origin project.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "uBlock filters – Badware risks",
                url: URL(string: "https://ublockorigin.github.io/uAssetsCDN/filters/badware.min.txt")!,
                category: FilterListCategory.security,
                description: "Blocks sites documented to install adware or malware, or to steal login credentials.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "uBlock filters – Quick fixes",
                url: URL(string: "https://ublockorigin.github.io/uAssetsCDN/filters/quick-fixes.min.txt")!,
                category: FilterListCategory.allowlists,
                description: "Short-term rules that fix sites broken by other filter lists.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "uBlock filters – Unbreak",
                url: URL(string: "https://ublockorigin.github.io/uAssetsCDN/filters/unbreak.min.txt")!,
                category: FilterListCategory.allowlists,
                description: "Rules that keep sites working when default lists break them.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList",
                url: URL(string: "https://cdn.jsdelivr.net/gh/uBlockOrigin/uAssetsCDN@main/thirdparties/easylist.txt")!,
                category: FilterListCategory.ads,
                description: "Blocks ads on websites, from the EasyList project."),
            FilterList(
                id: UUID(), name: "Online Malicious URL Blocklist",
                url: URL(string: "https://curbengh.github.io/malware-filter/urlhaus-filter-vivaldi-online.txt")!,
                category: FilterListCategory.security,
                description: "Blocks URLs that distribute malware, based on URLhaus data."),
            FilterList(
                id: UUID(), name: "uBlock filters – Annoyances",
                url: URL(string: "https://ublockorigin.github.io/uAssetsCDN/filters/annoyances.min.txt")!,
                category: FilterListCategory.annoyances,
                description: "Hides annoying page elements, such as overlays and promotional banners, from the uBlock Origin project.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "uBlock filters – Cookie Notices",
                url: URL(string: "https://ublockorigin.github.io/uAssetsCDN/filters/annoyances-cookies.txt")!,
                category: FilterListCategory.annoyances,
                description: "Blocks cookie notices on web pages.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList – Cookie Notices",
                url: URL(string: "https://ublockorigin.github.io/uAssetsCDN/thirdparties/easylist-cookies.txt")!,
                category: FilterListCategory.annoyances,
                description: "Blocks cookie notices on web pages."),
            FilterList(
                id: UUID(), name: "EasyList – Annoyances",
                url: URL(string: "https://ublockorigin.github.io/uAssetsCDN/thirdparties/easylist-annoyances.txt")!,
                category: FilterListCategory.annoyances,
                description: "Hides miscellaneous annoyances on websites, from the EasyList project."),
            FilterList(
                id: UUID(), name: "wBlock Ad and Tracking Hosts",
                url: Self.adTrackingHostsURL, category: FilterListCategory.privacy,
                description: "Blocks ad and tracking hosts that the other lists only block in part.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "HaGeZi Referral Allowlist",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/whitelist-referral.txt"
                )!, category: FilterListCategory.allowlists,
                description:
                    "Unblocks affiliate and tracking referral links that otherwise break in emails, search results, and redirects.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Actually Legitimate URL Shortener Tool",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/mac_v3/filters/251_optimized.txt"
                )!, category: FilterListCategory.privacy,
                description: "Automatically removes unnecessary '$' and '&' values from URLs, making them easier to copy from the URL bar and pasting elsewhere as links. Already included in Dandelion Sprout's Annoyances List.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Social Media Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/4_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description: "Filter for social media widgets such as 'Like' and 'Share' buttons and more."),
            FilterList(
                id: UUID(), name: "Fanboy's Social Blocking List",
                url: URL(string: "https://easylist.to/easylist/fanboy-social.txt")!,
                category: FilterListCategory.annoyances,
                description:
                    "Hides share and follow buttons on any site, including many that AdGuard Social Media Filter misses."),
            FilterList(
                id: UUID(), name: "Stevo's AI Blocklist",
                url: Self.stevoAIBlocklistURL, category: FilterListCategory.annoyances,
                description:
                    "Hides website features that use generative AI and AI-generated content."
            ),
            FilterList(
                id: UUID(), name: "AdGuard Mail Tracking Protection Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/25_optimized.txt"
                )!, category: FilterListCategory.privacy,
                description: "This filter blocks tracking pixels in email clients."),
            FilterList(
                id: UUID(), name: "Block Outsider Intrusion into LAN",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/258_optimized.txt"
                )!, category: FilterListCategory.privacy,
                description:
                    "Prevents public Internet sites from digging into your LAN files.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Dandelion Sprout's Anti-Malware List",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/259_optimized.txt"
                )!, category: FilterListCategory.security,
                description: "Blocks more malware than most other major anti-malware lists - domains and URL patterns used in malware redirection chains, IP addresses that are solely used by malware, PUP nags, and a few scammers. Already included in Dandelion Sprout's Annoyances List."),
            FilterList(
                id: UUID(), name: "Peter Lowe's Blocklist",
                url: URL(
                    string:
                        "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=1&mimetype=plaintext"
                )!, category: FilterListCategory.multipurpose,
                description: "Filter that blocks ads, trackers, and other nasty things."),
            FilterList(
                id: UUID(), name: "Adblock Warning Removal List",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/207_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description: "Removes anti-adblock warnings and other obtrusive messages."),
            FilterList(
                id: UUID(), name: "AdGuard Allowlist",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/10_optimized.txt"
                )!, category: FilterListCategory.allowlists,
                description: "Filter that unblocks search ads in Google, DuckDuckGo, Bing, or Yahoo and self-promotion on websites."),
            FilterList(
                id: UUID(), name: "Bypass Paywalls Clean Filter",
                url: URL(
                    string:
                        "https://pub-d303b9085c0b41b5aa749fc74609d4d9.r2.dev/bpc-paywall-filter.txt"
                )!, category: FilterListCategory.annoyances,
                description:
                    "Safari cannot apply this list's inline-script rules. Enable Bypass Paywalls Clean in Userscripts for supported English-language sites."
            ),
            FilterList(
                id: UUID(), name: "AdGuard Experimental Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/5_optimized.txt"
                )!, category: FilterListCategory.experimental,
                description: "Filter designed to test certain hazardous filtering rules before they are added to the basic filters."),
        ]

        filterLists.append(contentsOf: [
            FilterList(
                id: UUID(), name: "Liste AR",
                url: URL(string: "https://easylist-downloads.adblockplus.org/Liste_AR.txt")!,
                category: .foreign, description: "Additional filter list for websites in Arabic.",
                languages: ["ar", "kab"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Bulgarian list",
                url: URL(string: "https://stanev.org/abp/adblock_bg.txt")!, category: .foreign,
                description: "Additional filter list for websites in Bulgarian.", languages: ["bg", "mk"],
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Chinese filter",
                url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/224.txt")!,
                category: .foreign,
                description:
                    "EasyList China + AdGuard Chinese filter. Filter list that specifically removes ads on websites in Chinese language.",
                languages: ["ug", "zh"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "EasyList Czech and Slovak",
                url: URL(string: "https://raw.githubusercontent.com/tomasko126/easylistczechandslovak/master/filters.txt")!,
                category: .foreign,
                description: "Additional filter list for websites in Czech and Slovak.",
                languages: ["cs", "sk"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Dutch filter",
                url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/8.txt")!,
                category: .foreign,
                description:
                    "EasyList Dutch + AdGuard Dutch filter. Filter list that specifically removes ads on websites in Dutch language.",
                languages: ["af", "fy", "nl"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "Estonian List", url: URL(string: "https://ubo-et.lepik.io/list.txt")!,
                category: .foreign, description: "Filter for ad blocking on Estonian sites.",
                languages: ["et"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Adblock List for Finland",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/finnish-easylist-addition/finnish-easylist-addition/gh-pages/Finland_adb.txt"
                )!, category: .foreign, description: "Finnish ad blocking filter list.",
                languages: ["fi"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard French filter",
                url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/16.txt")!,
                category: .foreign,
                description:
                    "Liste FR + AdGuard French filter. Filter list that specifically removes ads on websites in French language.",
                languages: ["ar", "br", "ff", "fr", "kab", "lb", "oc", "son"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "EasyList Germany",
                url: URL(string: "https://easylist.to/easylistgermany/easylistgermany.txt")!,
                category: .foreign, description: "Additional filter list for websites in German.",
                languages: ["de", "dsb", "hsb", "lb", "rm"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "Greek AdBlock Filter",
                url: URL(string: "https://www.void.gr/kargig/void-gr-filters.txt")!,
                category: .foreign, description: "Additional filter list for websites in Greek.",
                languages: ["el"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Hebrew",
                url: URL(string: "https://raw.githubusercontent.com/easylist/EasyListHebrew/master/EasyListHebrew.txt")!,
                category: .foreign, description: "Additional filter list for websites in Hebrew.",
                languages: ["he"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "IndianList",
                url: URL(string: "https://easylist-downloads.adblockplus.org/indianlist.txt")!,
                category: .foreign,
                description:
                    "Additional filter list for websites in Hindi, Tamil and other Dravidian and Indic languages.",
                languages: [
                    "as", "bn", "gu", "hi", "kn", "ml", "mr", "ne", "pa", "sat", "si", "ta", "te"
                ], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Hungarian filter",
                url: URL(string: "https://cdn.jsdelivr.net/gh/hufilter/hufilter@gh-pages/hufilter-ublock.txt")!,
                category: .foreign,
                description:
                    "Hufilter. Filter list that specifically removes ads, privacy threats, and security risks on websites in the Hungarian language.",
                languages: ["hu"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Icelandic ABP List",
                url: URL(string: "https://raw.githubusercontent.com/brave/adblock-lists/master/custom/is.txt")!,
                category: .foreign, description: "Additional filter list for websites in Icelandic.",
                languages: ["is"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "ABPindo",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/ABPindo/indonesianadblockrules/master/subscriptions/abpindo.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Indonesian and Malay.",
                languages: ["id", "ms"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdBlockID",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/120_optimized.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Indonesian and Malay.",
                languages: ["id", "ms"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Italy",
                url: URL(string: "https://easylist-downloads.adblockplus.org/easylistitaly.txt")!,
                category: .foreign, description: "Additional filter list for websites in Italian.",
                languages: ["fur", "it", "lij", "sc"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Japanese filter",
                url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/7.txt")!,
                category: .foreign,
                description: "Filter that enables ad blocking on websites in Japanese language.",
                languages: ["ja"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "filterslists-KO",
                url: URL(
                    string:
                        "https://cdn.jsdelivr.net/npm/@filteringdev/filterslists-ko@latest/dist/filterslist-uBlockOrigin-classic.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Korean.",
                languages: ["ko"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Latvian List",
                url: URL(string: "https://raw.githubusercontent.com/Latvian-List/adblock-latvian/master/lists/latvian-list.txt")!,
                category: .foreign, description: "Additional filter list for websites in Latvian.",
                languages: ["lv"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Lithuania",
                url: URL(
                    string:
                        "https://cdn.jsdelivr.net/gh/EasyList-Lithuania/easylist_lithuania@master/easylistlithuania.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Lithuanian.",
                languages: ["lt"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Macedonian adBlock Filters",
                url: URL(string: "https://raw.githubusercontent.com/DeepSpaceHarbor/Macedonian-adBlock-Filters/master/Filters")!,
                category: .foreign, description: "Blocks ads and trackers on various Macedonian websites.",
                languages: ["mk"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Dandelion Sprout's Nordic Filters",
                url: URL(string: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianList.txt")!,
                category: .foreign,
                description:
                    "This list covers websites for Norway, Denmark, Iceland, Danish territories, and the Sami indigenous population.",
                languages: ["nb", "nn", "no", "da", "is"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Official Polish filters for AdBlock, uBlock Origin & AdGuard",
                url: URL(string: "https://raw.githubusercontent.com/MajkiIT/polish-ads-filter/master/polish-adblock-filters/adblock.txt")!,
                category: .foreign, description: "Additional filter list for websites in Polish.",
                languages: ["szl", "pl"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "KAD - Anti-Scam",
                url: URL(
                    string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/232_optimized.txt")!,
                category: .foreign,
                description:
                    "Filter that protects against various types of scams in the Polish network, such as mass text messaging, fake online stores, etc.",
                languages: ["pl"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "CERT.PL's Warning List",
                url: URL(string: "https://hole.cert.pl/domains/v2/domains_ublock.txt")!,
                category: .foreign, description: "Blocks phishing and malware domains flagged by CERT Polska.",
                languages: ["szl", "pl"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "road-block light",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/tcptomato/ROad-Block/master/road-block-filters-light.txt"
                )!, category: .foreign, description: "Romanian ad blocking filter subscription.",
                languages: ["ro"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "RU AdList",
                url: URL(string: "https://cdn.jsdelivr.net/gh/dimisa-RUAdList/RUAdListCDN@main/lists/ruadlist.ubo.min.txt")!,
                category: .foreign, description: "Filter that enables ad blocking on websites in Russian language.",
                languages: ["be", "kk", "tt", "ru", "uz"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "RU AdList: Counters",
                url: URL(string: "https://cdn.jsdelivr.net/gh/easylist/ruadlist@master/cntblock.txt")!,
                category: .foreign, description: "Blocks visitor counters on Russian-language websites.",
                languages: ["be", "kk", "tt", "ru", "uz"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "Dandelion Sprout's Serbo-Croatian List",
                url: URL(string: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/SerboCroatianList.txt")!,
                category: .foreign,
                description: "A filter list for websites in Serbian, Montenegrin, Croatian, and Bosnian.",
                languages: ["bs", "hr", "sr"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Spanish/Portuguese filter",
                url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/9.txt")!,
                category: .foreign,
                description:
                    "Filter list that specifically removes ads on websites in Spanish, Portuguese, and Brazilian Portuguese languages.",
                languages: ["an", "ast", "ca", "cak", "es", "eu", "gl", "gn", "trs", "pt", "quz"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "EasyList Spanish",
                url: URL(string: "https://easylist-downloads.adblockplus.org/easylistspanish.txt")!,
                category: .foreign, description: "Additional filter list for websites in Spanish.",
                languages: ["an", "ast", "ca", "cak", "es", "eu", "gl", "gn", "trs", "quz"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "Frellwit's Swedish Filter",
                url: URL(string: "https://raw.githubusercontent.com/lassekongo83/Frellwits-filter-lists/swefilter/swefilter.min.txt")!,
                category: .foreign,
                description:
                    "Filter that aims to remove regional Swedish ads, tracking, social media, annoyances, sponsored articles etc.",
                languages: ["sv"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Thailand",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/easylist-thailand/easylist-thailand/master/subscription/easylist-thailand.txt"
                )!, category: .foreign, description: "Filter that blocks ads on Thai sites.",
                languages: ["th"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Turkish filter",
                url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/13.txt")!,
                category: .foreign,
                description:
                    "Filter list that specifically removes ads on websites in Turkish language.",
                languages: ["tr"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Ukrainian filter",
                url: URL(string: "https://filters.adtidy.org/extension/ublock/filters/23.txt")!,
                category: .foreign,
                description: "Filter that enables ad blocking on websites in Ukrainian language.",
                languages: ["uk"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "ABPVN List",
                url: URL(string: "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn_ublock.txt")!,
                category: .foreign, description: "Vietnamese adblock filter list.",
                languages: ["vi"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "PersianBlockerNG",
                url: URL(string: "https://cdn.jsdelivr.net/gh/PersianBlocker/PersianBlocker@main/PersianBlocker.txt")!,
                category: .foreign, description: "Additional filter list for websites in Persian.",
                languages: ["fa", "ps", "tg"], trustLevel: "high"),
        ])
        filterLists.append(
            FilterList(
                id: UUID(), name: "EasyPrivacy",
                url: URL(
                    string:
                        "https://cdn.jsdelivr.net/gh/uBlockOrigin/uAssetsCDN@main/thirdparties/easyprivacy.txt"
                )!, category: FilterListCategory.privacy,
                description:
                    "Privacy protection supplement for EasyList."))

        // Multi Pro Mini is the size-optimized browser/mobile list. Keep its catalog
        // identity on every platform; it remains opt-in like other extras.
        filterLists.append(
            FilterList(
                id: UUID(), name: "HaGeZi Multi Pro Mini",
                url: URL(
                    string:
                        "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.mini.txt"
                )!, category: FilterListCategory.multipurpose,
                description:
                    "Extensive blocklist targeting ads, trackers, and other unwanted content."))

        for index in filterLists.indices {
            filterLists[index].isSelected = Self.recommendedFilterNames.contains(filterLists[index].name)
        }

        return filterLists
    }

    /// Checks if a filter file exists locally
    func filterFileExists(_ filter: FilterList) -> Bool {
        guard let containerURL = getSharedContainerURL() else { return false }
        return ContentBlockerIncrementalCache.existingLocalFileURL(
            for: filter,
            containerURL: containerURL
        ) != nil
    }

    /// Size and leading header of the local copy, without reading the whole list.
    func localFilterHeader(_ filter: FilterList, length: Int = 8192) -> (size: Int, header: String)? {
        guard let containerURL = getSharedContainerURL(),
              let url = ContentBlockerIncrementalCache.existingLocalFileURL(for: filter, containerURL: containerURL),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (size, String(decoding: (try? handle.read(upToCount: length)) ?? Data(), as: UTF8.self))
    }

    /// Gets the URL for the shared container
    func getSharedContainerURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value)
    }

    /// Reads the content of a filter list from the local file system
    func readLocalFilterContent(_ filter: FilterList) -> String? {
        guard let containerURL = getSharedContainerURL() else { return nil }
        guard let fileURL = ContentBlockerIncrementalCache.existingLocalFileURL(
            for: filter,
            containerURL: containerURL
        ) else { return nil }

        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            Task {
                await ConcurrentLogManager.shared.error(
                    .filterUpdate, LocalizedStrings.text("Failed to read filter content"),
                    metadata: ["filter": filter.name, "error": LogErrorDescriber.describe(error)])
            }
            return nil
        }
    }
}
