//
//  FilterListLoader.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import Foundation
import wBlockCoreService

class FilterListLoader {
    #if os(macOS)
        static let minimalFilterNames: Set<String> = ["AdGuard Base Filter"]
        static let recommendedFilterNames: Set<String> = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "AdGuard URL Tracking Protection Filter",
            "Actually Legitimate URL Shortener Tool",
            "Peter Lowe's Blocklist",
            "AdGuard Cookie Notices",
        ]
    #else
        static let minimalFilterNames: Set<String> = ["AdGuard Base Filter", "AdGuard Mobile Filter"]
        static let recommendedFilterNames: Set<String> = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "AdGuard URL Tracking Protection Filter",
            "Actually Legitimate URL Shortener Tool",
            "Peter Lowe's Blocklist",
            "AdGuard Cookie Notices",
            "AdGuard Mobile Filter",
        ]
    #endif

    // Lists that prompt an "essential protection" warning before they are disabled.
    // Cookie Notices is on by default (#655) but is a convenience, not protection.
    static let essentialFilterNames: Set<String> = recommendedFilterNames.subtracting(["AdGuard Cookie Notices"])

    private static let stevoAIBlocklistURL = URL(
        string: "https://raw.githubusercontent.com/Stevoisiak/Stevos-AI-Blocklist/refs/heads/main/GenAI-Blocklist.txt"
    )!

    private static let filterURLMigrations: [String: URL] = [
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_17_TrackParam/filter.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/mac_v3/filters/17_optimized.txt")!,
        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/LegitimateURLShortener.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/mac_v3/filters/251_optimized.txt")!,
        "https://raw.githubusercontent.com/ABPindo/indonesianadblockrules/master/subscriptions/abpindo.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/102_optimized.txt")!,
        "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn_adguard.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/214_optimized.txt")!,
        "https://raw.githubusercontent.com/finnish-easylist-addition/finnish-easylist-addition/gh-pages/Finland_adb.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/233_optimized.txt")!,
        "https://raw.githubusercontent.com/realodix/AdBlockID/main/dist/adblockid.adfl.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/120_optimized.txt")!,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/224_optimized.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/224_optimized.txt")!,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/8_optimized.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/8_optimized.txt")!,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/16_optimized.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/16_optimized.txt")!,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/6_optimized.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/6_optimized.txt")!,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/7_optimized.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/7_optimized.txt")!,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/1_optimized.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/1_optimized.txt")!,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/9_optimized.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/9_optimized.txt")!,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/13_optimized.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/13_optimized.txt")!,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/23_optimized.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/23_optimized.txt")!,
        "https://stanev.org/abp/adblock_bg.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/103_optimized.txt")!,
        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianExperimentalList%20alternate%20versions/NordicFiltersAdGuard.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/249_optimized.txt")!,
        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/SerboCroatianList.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/252_optimized.txt")!,
        "https://raw.githubusercontent.com/tomasko126/easylistczechandslovak/master/filters.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/105_optimized.txt")!,
        "https://raw.githubusercontent.com/easylist/EasyListHebrew/master/EasyListHebrew.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/108_optimized.txt")!,
        "https://easylist-downloads.adblockplus.org/easylistitaly.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/26_optimized.txt")!,
        "https://raw.githubusercontent.com/EasyList-Lithuania/easylist_lithuania/master/easylistlithuania.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/110_optimized.txt")!,
        "https://raw.githubusercontent.com/easylist-thailand/easylist-thailand/master/subscription/easylist-thailand.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/202_optimized.txt")!,
        "https://adblock.ee/list.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/218_optimized.txt")!,
        "https://raw.githubusercontent.com/lassekongo83/Frellwits-filter-lists/master/Frellwits-Swedish-Filter.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/243_optimized.txt")!,
        "https://www.void.gr/kargig/void-gr-filters.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/121_optimized.txt")!,
        "https://cdn.jsdelivr.net/gh/hufilter/hufilter@gh-pages/hufilter-adguard.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/203_optimized.txt")!,
        "https://adblock.gardar.net/is.abp.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/119_optimized.txt")!,
        "https://easylist-downloads.adblockplus.org/indianlist.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/253_optimized.txt")!,
        "https://raw.githubusercontent.com/FiltersHeroes/KAD/master/KAD.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/232_optimized.txt")!,
        "https://raw.githubusercontent.com/Latvian-List/adblock-latvian/master/lists/latvian-list.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/111_optimized.txt")!,
        "https://filters.adtidy.org/extension/safari/filters/227_optimized.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/227_optimized.txt")!,
        "https://easylist-downloads.adblockplus.org/Liste_AR.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/112_optimized.txt")!,
        "https://raw.githubusercontent.com/RandomAdversary/Macedonian-adBlock-Filters/master/Filters":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/254_optimized.txt")!,
        "https://raw.githubusercontent.com/MajkiIT/polish-ads-filter/master/polish-adblock-filters/adblock.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/27_optimized.txt")!,
        "https://raw.githubusercontent.com/tcptomato/ROad-Block/master/road-block-filters-light.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/236_optimized.txt")!,
        // 2026-09: the worker now mirrors BPC into R2; reads go to the bucket so
        // update checks stop counting against the worker's daily quota.
        "https://bpc-filter-proxy.wmailrelayb8d890.workers.dev": URL(string: "https://pub-d303b9085c0b41b5aa749fc74609d4d9.r2.dev/bpc-paywall-filter.txt")!,
        "https://bpc-filter-proxy.wmailrelayb8d890.workers.dev/": URL(string: "https://pub-d303b9085c0b41b5aa749fc74609d4d9.r2.dev/bpc-paywall-filter.txt")!,
        "https://raw.githubusercontent.com/List-KR/List-KR/refs/heads/master/filter-AdGuard-forward.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/227_optimized.txt")!,
        "https://raw.githubusercontent.com/List-KR/List-KR/master/filter-AdGuard-forward.txt": URL(
            string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/227_optimized.txt")!,
        "https://raw.githubusercontent.com/easylist/easylist/refs/heads/master/fanboy-addon/fanboy_ai_suggestions.txt": stevoAIBlocklistURL,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/260.txt": stevoAIBlocklistURL,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/260_optimized.txt": stevoAIBlocklistURL,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/25.txt": URL(
            string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/25_optimized.txt")!,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/10.txt": URL(
            string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/10_optimized.txt")!,
        // AdGuard Mobile Filter moved to the GitHub registry so it gets the same
        // jsDelivr and adtidy fallbacks as the other AdGuard lists (#912).
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_11_Mobile/filter.txt":
            URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/ios/filters/11_optimized.txt")!,
        "https://filters.adtidy.org/ios/filters/11.txt": URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/ios/filters/11_optimized.txt")!,
        "https://filters.adtidy.org/ios/filters/11_optimized.txt": URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/ios/filters/11_optimized.txt")!,
    ]

    /// Legacy names whose list came from a different source than the current
    /// entry, with the header title that identifies that old content. Their
    /// cache must not be carried over under the new name, and a cache already
    /// carried over by an earlier release is dropped so the new source is fetched.
    private static let replacedSourceLegacyTitles: [String: String] = [
        "EasyList Italy": "! Title: EasyList Italy",
        "Official Polish filters for AdBlock, uBlock Origin & AdGuard": "! Title: Official Polish filters",
        "Fanboy's Anti-AI Suggestions": "! Title: Fanboy's Anti-AI"
    ]

    /// Built-in lists removed from the catalog, matched by URL fragment.
    private static let retiredBuiltInURLFragments = [
        "d3ward/toolz",
        "platforms/extension/safari/filters/208_optimized.txt",  // Online Malicious URL Blocklist (#864)
        "platforms/extension/safari/filters/122_optimized.txt",  // Fanboy's Annoyances Filter (#877)
        "easylist.to/easylist/fanboy-social.txt",  // Fanboy's Social Blocking List (#877)
        "raw.githubusercontent.com/cjx82630/cjxlist/master/cjx-annoyance.txt",  // CJX's Annoyances List (#882)
        "raw.githubusercontent.com/easylist/easylistchina/master/easylistchina.txt",  // EasyList China (#882)
        "easylist-downloads.adblockplus.org/easylistdutch.txt",  // EasyList Dutch (#882)
        "easylist.to/easylistgermany/easylistgermany.txt",  // EasyList Germany (#882)
        "easylist-downloads.adblockplus.org/easylistpolish.txt",  // EasyList Polish (#882)
        "easylist-downloads.adblockplus.org/easylistportuguese.txt",  // EasyList Portuguese (#882)
        "easylist-downloads.adblockplus.org/easylistspanish.txt",  // EasyList Spanish (#882)
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
        "hole.cert.pl/domains/",  // CERT.PL's Warning List, almost entirely inside KAD (#931)
    ]

    static func isRetiredBuiltIn(_ filter: FilterList) -> Bool {
        !filter.isCustom
            && (filter.name == "d3Host List by d3ward"
                || retiredBuiltInURLFragments.contains { filter.url.absoluteString.contains($0) })
    }

    /// New built-in names and the names used by the previous catalog release.
    private static let filterNameMigrations: [String: [String]] = [
        "AdGuard Italian filter": ["EasyList Italy"],
        "AdGuard Polish filter": ["Official Polish filters for AdBlock, uBlock Origin & AdGuard"],
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
                id: UUID(), name: "AdGuard Base Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/2_optimized.txt"
                )!, category: FilterListCategory.ads, isSelected: true,
                description: "EasyList + AdGuard English filter. This filter is necessary for quality ad blocking."),
            FilterList(
                id: UUID(), name: "AdGuard Tracking Protection Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/3_optimized.txt"
                )!, category: FilterListCategory.privacy, isSelected: true,
                description: "The most comprehensive list of various online counters and web analytics tools. Use this filter if you do not want your actions on the Internet to be tracked."),
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
                id: UUID(), name: "AdGuard URL Tracking Protection Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/mac_v3/filters/17_optimized.txt"
                )!, category: FilterListCategory.privacy, isSelected: true,
                description: "Filter that enhances privacy by removing tracking parameters from URLs.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Actually Legitimate URL Shortener Tool",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/mac_v3/filters/251_optimized.txt"
                )!, category: FilterListCategory.privacy, isSelected: true,
                description: "Automatically removes unnecessary '$' and '&' values from URLs, making them easier to copy from the URL bar and pasting elsewhere as links. Already included in Dandelion Sprout's Annoyances List.",
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Cookie Notices",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/18_optimized.txt"
                )!, category: FilterListCategory.annoyances, isSelected: true,
                description: "Blocks cookie notices on web pages."),
            FilterList(
                id: UUID(), name: "AdGuard Popups",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/19_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description:
                    "Blocks all kinds of pop-ups that are not necessary for websites' operation according to our Filter policy."),
            FilterList(
                id: UUID(), name: "AdGuard Mobile App Banners",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/20_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description: "Blocks irritating banners that promote mobile apps of websites."),
            FilterList(
                id: UUID(), name: "AdGuard Other Annoyances",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/21_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description:
                    "Blocks irritating elements that do not fall under popular categories of annoyances, such as website promotional offers and restrictions on copying and text selection."),
            FilterList(
                id: UUID(), name: "AdGuard Widgets",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/22_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description: "Blocks annoying third-party widgets: online assistants, live support chats, etc."),
            FilterList(
                id: UUID(), name: "AdGuard Social Media Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/4_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description: "Filter for social media widgets such as 'Like' and 'Share' buttons and more."),
            FilterList(
                id: UUID(), name: "Stevo's AI Blocklist",
                url: Self.stevoAIBlocklistURL, category: FilterListCategory.annoyances,
                description:
                    "A filter list that hides website features which use generative AI and AI-generated content."
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
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/204_optimized.txt"
                )!, category: FilterListCategory.multipurpose, isSelected: true,
                description: "Filter that blocks ads, trackers, and other nasty things."),
            FilterList(
                id: UUID(), name: "Adblock Warning Removal List",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/207_optimized.txt"
                )!, category: FilterListCategory.annoyances, isSelected: true,
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
                url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/112_optimized.txt")!,
                category: .foreign, description: "Additional filter list for websites in Arabic.",
                languages: ["ar"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Bulgarian list",
                url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/103_optimized.txt")!, category: .foreign,
                description: "Additional filter list for websites in Bulgarian.", languages: ["bg"],
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Chinese filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/224_optimized.txt"
                )!, category: .foreign,
                description:
                    "EasyList China + AdGuard Chinese filter. Filter list that specifically removes ads on websites in Chinese language.",
                languages: ["zh"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "EasyList Czech and Slovak",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/105_optimized.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Czech and Slovak.",
                languages: ["cs", "sk"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Dutch filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/8_optimized.txt"
                )!, category: .foreign,
                description:
                    "EasyList Dutch + AdGuard Dutch filter. Filter list that specifically removes ads on websites in Dutch language.",
                languages: ["nl"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "Estonian List", url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/218_optimized.txt")!,
                category: .foreign, description: "Filter for ad blocking on Estonian sites.",
                languages: ["et"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Adblock List for Finland",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/233_optimized.txt"
                )!, category: .foreign, description: "Finnish ad blocking filter list.",
                languages: ["fi"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard French filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/16_optimized.txt"
                )!, category: .foreign,
                description:
                    "Liste FR + AdGuard French filter. Filter list that specifically removes ads on websites in French language.",
                languages: ["fr", "ar"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard German filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/6_optimized.txt"
                )!, category: .foreign,
                description:
                    "EasyList Germany + AdGuard German filter. Filter list that specifically removes ads on websites in German language.",
                languages: ["de"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "Greek AdBlock Filter",
                url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/121_optimized.txt")!,
                category: .foreign, description: "Additional filter list for websites in Greek.",
                languages: ["el"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Hebrew",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/108_optimized.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Hebrew.", languages: ["he"],
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "IndianList",
                url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/253_optimized.txt")!,
                category: .foreign,
                description:
                    "Additional filter list for websites in Hindi, Tamil and other Dravidian and Indic languages.",
                languages: [
                    "hi", "si", "ne", "bn", "as", "gu", "kn", "mai", "ml", "mr", "or", "pa",
                    "ta", "te"
                ], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Hungarian filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/203_optimized.txt"
                )!, category: .foreign,
                description:
                    "Hufilter. Filter list that specifically removes ads, privacy threats, and security risks on websites in the Hungarian language.",
                languages: ["hu"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Icelandic ABP List",
                url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/119_optimized.txt")!, category: .foreign,
                description: "Additional filter list for websites in Icelandic.", languages: ["is"],
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "ABPindo",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/102_optimized.txt"
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
                id: UUID(), name: "AdGuard Italian filter",
                url: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/26_optimized.txt")!,
                category: .foreign, description: "EasyList Italy + AdGuard Italian filter. Filter list that specifically removes ads on websites in the Italian language.",
                languages: ["it"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Japanese filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/7_optimized.txt"
                )!, category: .foreign,
                description: "Filter that enables ad blocking on websites in Japanese language.",
                languages: ["ja"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "filterslists-KO",
                url: URL(
                    string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/227_optimized.txt")!,
                category: .foreign,
                description:
                    "The filterslist-KO Classic filter list for AdGuard blocks ads and disables anti-adblock scripts on Korean-language websites and apps.",
                languages: ["ko"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Latvian List",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/111_optimized.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Latvian.", languages: ["lv"],
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Lithuania",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/110_optimized.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Lithuanian.",
                languages: ["lt"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Macedonian adBlock Filters",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/254_optimized.txt"
                )!, category: .foreign,
                description: "Blocks ads and trackers on various Macedonian websites.",
                languages: ["mk"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Dandelion Sprout's Nordic Filters",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/249_optimized.txt"
                )!, category: .foreign,
                description:
                    "This list covers websites for Norway, Denmark, Iceland, Danish territories, and the Sami indigenous population.",
                languages: ["nb", "nn", "da", "is", "fo", "kl", "se", "smn", "sma", "smj", "sms", "sje", "sju", "sjd"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Polish filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/27_optimized.txt"
                )!, category: .foreign,
                description: "Official Polish filters for AdBlock, uBlock Origin & AdGuard + AdGuard Polish filter. Filter list that specifically removes ads on websites in the Polish language.", languages: ["pl"],
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "KAD - Anti-Scam",
                url: URL(
                    string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/232_optimized.txt")!,
                category: .foreign,
                description:
                    "Filter that protects against various types of scams in the Polish network, such as mass text messaging, fake online stores, etc.",
                languages: ["pl"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "road-block light",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/236_optimized.txt"
                )!, category: .foreign, description: "Romanian ad blocking filter subscription.",
                languages: ["ro"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Russian filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/1_optimized.txt"
                )!, category: .foreign,
                description: "Filter that enables ad blocking on websites in Russian language.",
                languages: ["ru"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "Dandelion Sprout's Serbo-Croatian List",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/252_optimized.txt"
                )!, category: .foreign,
                description:
                    "A filter list for websites in Serbian, Montenegrin, Croatian, and Bosnian.",
                languages: ["sr", "cnr", "hr", "bs"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Spanish/Portuguese filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/9_optimized.txt"
                )!, category: .foreign,
                description:
                    "Filter list that specifically removes ads on websites in Spanish, Portuguese, and Brazilian Portuguese languages.",
                languages: ["es", "pt"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "Frellwit's Swedish Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/243_optimized.txt"
                )!, category: .foreign,
                description:
                    "Filter that aims to remove regional Swedish ads, tracking, social media, annoyances, sponsored articles etc.",
                languages: ["sv"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Thailand",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/202_optimized.txt"
                )!, category: .foreign, description: "Filter that blocks ads on Thai sites.",
                languages: ["th"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Turkish filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/13_optimized.txt"
                )!, category: .foreign,
                description:
                    "Filter list that specifically removes ads on websites in Turkish language.",
                languages: ["tr"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Ukrainian filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/23_optimized.txt"
                )!, category: .foreign,
                description: "Filter that enables ad blocking on websites in Ukrainian language.",
                languages: ["uk"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "ABPVN List",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/214_optimized.txt"
                )!, category: .foreign, description: "Vietnamese adblock filter list.",
                languages: ["vi"], trustLevel: "high"),
        ])
        filterLists.append(
            FilterList(
                id: UUID(), name: "EasyPrivacy",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/118_optimized.txt"
                )!, category: FilterListCategory.privacy, isSelected: true,
                description:
                    "Privacy protection supplement for EasyList."))
        #if os(iOS)
            filterLists.append(
                FilterList(
                    id: UUID(), name: "AdGuard Mobile Filter",
                    url: URL(
                        string:
                            "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/ios/filters/11_optimized.txt"
                    )!, category: FilterListCategory.ads, isSelected: true,
                    description: "Filter for all known mobile ad networks. Useful for mobile devices. Recommended for iOS and iPadOS."))
        #endif

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
