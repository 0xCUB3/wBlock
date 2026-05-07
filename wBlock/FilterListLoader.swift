//
//  FilterListLoader.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import Foundation
import wBlockCoreService

class FilterListLoader {
    static var isNativeCompilerEnabled: Bool { true }

    static var basicFilterNames: Set<String> {
        nativeCompilerBasicFilterNames
    }

    static var recommendedFilterNames: Set<String> {
        var names = nativeCompilerRecommendedFilterNames
        #if os(iOS)
            names.insert("AdGuard – Mobile Ads")
        #endif
        return names
    }

    private static let nativeCompilerBasicFilterNames: Set<String> = [
        "uBlock filters – Ads",
        "uBlock filters – Unbreak",
        "uBlock filters – Quick fixes",
        "EasyList",
    ]

    private static let nativeCompilerRecommendedFilterNames: Set<String> = [
        "uBlock filters – Ads",
        "uBlock filters – Badware risks",
        "uBlock filters – Privacy",
        "uBlock filters – Unbreak",
        "uBlock filters – Quick fixes",
        "EasyList",
        "EasyPrivacy",
        "Online Malicious URL Blocklist",
        "Peter Lowe’s Ad and tracking server list",
    ]

    private let filterURLMigrations: [String: URL] = [
        "https://raw.githubusercontent.com/List-KR/List-KR/refs/heads/master/filter-AdGuard-forward.txt":
            URL(string: "https://cdn.jsdelivr.net/npm/@list-kr/filterslists@latest/dist/filterslist-uBlockOrigin-classic.txt")!,
        "https://raw.githubusercontent.com/List-KR/List-KR/master/filter-AdGuard-forward.txt": URL(
            string: "https://cdn.jsdelivr.net/npm/@list-kr/filterslists@latest/dist/filterslist-uBlockOrigin-classic.txt")!,
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_11_Mobile/filter.txt":
            URL(string: "https://filters.adtidy.org/extension/ublock/filters/11.txt")!,
    ]

    private let filterURLFragmentMigrations: [(fragment: String, url: URL)] = [
        ("filters/224_optimized.txt", URL(string: "https://filters.adtidy.org/extension/ublock/filters/224.txt")!),
        ("easylistchina/master/easylistchina.txt", URL(string: "https://filters.adtidy.org/extension/ublock/filters/224.txt")!),
        ("filters/8_optimized.txt", URL(string: "https://filters.adtidy.org/extension/ublock/filters/8.txt")!),
        ("easylistdutch.txt", URL(string: "https://filters.adtidy.org/extension/ublock/filters/8.txt")!),
        ("filters/16_optimized.txt", URL(string: "https://filters.adtidy.org/extension/ublock/filters/16.txt")!),
        ("liste_fr.txt", URL(string: "https://filters.adtidy.org/extension/ublock/filters/16.txt")!),
        ("filters/6_optimized.txt", URL(string: "https://easylist.to/easylistgermany/easylistgermany.txt")!),
        ("filters/7_optimized.txt", URL(string: "https://filters.adtidy.org/extension/ublock/filters/7.txt")!),
        ("filters/1_optimized.txt", URL(string: "https://raw.githubusercontent.com/easylist/ruadlist/master/RuAdList-uBO.txt")!),
        ("filters/9_optimized.txt", URL(string: "https://filters.adtidy.org/extension/ublock/filters/9.txt")!),
        ("easylistportuguese.txt", URL(string: "https://filters.adtidy.org/extension/ublock/filters/9.txt")!),
        ("filters/13_optimized.txt", URL(string: "https://filters.adtidy.org/extension/ublock/filters/13.txt")!),
        ("filters/23_optimized.txt", URL(string: "https://filters.adtidy.org/extension/ublock/filters/23.txt")!),
        ("filters/227_optimized.txt", URL(string: "https://cdn.jsdelivr.net/npm/@list-kr/filterslists@latest/dist/filterslist-uBlockOrigin-classic.txt")!),
        ("filter/abpvn_adguard.txt", URL(string: "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn_ublock.txt")!),
        ("hufilter-adguard.txt", URL(string: "https://cdn.jsdelivr.net/gh/hufilter/hufilter@gh-pages/hufilter-ublock.txt")!),
        ("NordicFiltersAdGuard.txt", URL(string: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianList.txt")!),
        ("https://adblock.ee/list.txt", URL(string: "https://ubo-et.lepik.io/list.txt")!),
        ("https://adblock.gardar.net/is.abp.txt", URL(string: "https://raw.githubusercontent.com/brave/adblock-lists/master/custom/is.txt")!),
        ("RandomAdversary/Macedonian-adBlock-Filters/master/Filters", URL(string: "https://raw.githubusercontent.com/DeepSpaceHarbor/Macedonian-adBlock-Filters/master/Filters")!),
        ("easylist-downloads.adblockplus.org/cntblock.txt", URL(string: "https://raw.githubusercontent.com/easylist/ruadlist/master/cntblock.txt")!),
    ]

    func localFileURL(for filter: FilterList) -> URL? {
        guard let containerURL = getSharedContainerURL() else { return nil }
        return containerURL.appendingPathComponent(
            ContentBlockerIncrementalCache.localFilename(for: filter)
        )
    }

    /// Migrates legacy filter filenames to the current stable filename.
    /// Custom filters used to be stored as `<name>.txt`; built-in filters also
    /// used name-only filenames before URL fingerprints were added.
    func migrateFilterFileIfNeeded(_ filter: FilterList) {
        guard let containerURL = getSharedContainerURL() else { return }

        let newURL = containerURL.appendingPathComponent(
            ContentBlockerIncrementalCache.localFilename(for: filter)
        )
        let oldURL = containerURL.appendingPathComponent(
            ContentBlockerIncrementalCache.legacyLocalFilename(for: filter)
        )

        guard !FileManager.default.fileExists(atPath: newURL.path),
            FileManager.default.fileExists(atPath: oldURL.path)
        else { return }

        do {
            if filter.isCustom {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
            } else {
                try FileManager.default.copyItem(at: oldURL, to: newURL)
            }
            Task {
                await ConcurrentLogManager.shared.info(
                    .system, "Migrated filter filename",
                    metadata: ["filter": filter.name, "to": newURL.lastPathComponent]
                )
            }
        } catch {
            Task {
                await ConcurrentLogManager.shared.error(
                    .system, "Failed migrating filter filename",
                    metadata: ["filter": filter.name, "error": "\(error)"]
                )
            }
        }
    }

    /// Updates any known legacy filter URLs to their current uBO-compatible endpoints.
    func migrateFilterURLs(in filters: [FilterList]) -> [FilterList] {
        filters.map { filter in
            let urlString = filter.url.absoluteString
            let newURL = filterURLMigrations[urlString]
                ?? filterURLFragmentMigrations.first { urlString.contains($0.fragment) }?.url
            guard let newURL, newURL != filter.url else {
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
        createNativeCompilerDefaultFilterLists()
    }

    private func makeNativeFilter(
        name: String,
        url: String,
        category: FilterListCategory,
        isSelected: Bool = false,
        description: String = "",
        languages: [String] = [],
        trustLevel: String? = nil
    ) -> FilterList {
        FilterList(
            id: UUID(),
            name: name,
            url: URL(string: url)!,
            category: category,
            isSelected: isSelected,
            description: description,
            languages: languages,
            trustLevel: trustLevel
        )
    }

    /// Creates a uBlock Origin dashboard-style catalog for the native compiler.
    /// URLs are taken from uBO's assets.json / Dashboard: Filter lists page and
    /// uBO-compatible endpoints so the native compiler sees the same syntax family
    /// it is meant to support.
    private func createNativeCompilerDefaultFilterLists() -> [FilterList] {
        var filterLists = createDefaultFilterLists()
        let replacedCoreNames: Set<String> = [
            "AdGuard Base Filter",
            "AdGuard Tracking Protection Filter",
            "AdGuard Cookie Notices",
            "AdGuard Popups",
            "AdGuard Mobile App Banners",
            "AdGuard Other Annoyances",
            "AdGuard Widgets",
            "AdGuard Social Media Filter",
            "Fanboy's Annoyances Filter",
            "Fanboy's Social Blocking List",
            "Fanboy's Anti-AI Suggestions",
            "Online Security Filter",
            "Peter Lowe's Blocklist",
            "Anti-Adblock List",
            "AdGuard Experimental Filter",
            "EasyPrivacy",
            "d3Host List by d3ward",
            "Hagezi Pro Mini",
            "AdGuard Mobile Filter",
        ]
        filterLists.removeAll { replacedCoreNames.contains($0.name) }

        let nativeCore: [FilterList] = [
            makeNativeFilter(name: "uBlock filters – Ads", url: "https://ublockorigin.github.io/uAssets/filters/filters.txt", category: .ads),
            makeNativeFilter(name: "uBlock filters – Badware risks", url: "https://ublockorigin.github.io/uAssets/filters/badware.txt", category: .security),
            makeNativeFilter(name: "uBlock filters – Privacy", url: "https://ublockorigin.github.io/uAssets/filters/privacy.txt", category: .privacy),
            makeNativeFilter(name: "uBlock filters – Unbreak", url: "https://ublockorigin.github.io/uAssets/filters/unbreak.txt", category: .ads),
            makeNativeFilter(name: "uBlock filters – Quick fixes", url: "https://ublockorigin.github.io/uAssets/filters/quick-fixes.txt", category: .ads),
            makeNativeFilter(name: "EasyList", url: "https://ublockorigin.github.io/uAssets/thirdparties/easylist.txt", category: .ads),
            makeNativeFilter(name: "EasyPrivacy", url: "https://ublockorigin.github.io/uAssets/thirdparties/easyprivacy.txt", category: .privacy),
            makeNativeFilter(name: "Online Malicious URL Blocklist", url: "https://malware-filter.gitlab.io/urlhaus-filter/urlhaus-filter-ag-online.txt", category: .security),
            makeNativeFilter(name: "Peter Lowe’s Ad and tracking server list", url: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=1&mimetype=plaintext", category: .annoyances),
            makeNativeFilter(name: "uBlock filters – Annoyances", url: "https://ublockorigin.github.io/uAssets/filters/annoyances.txt", category: .annoyances),
            makeNativeFilter(name: "uBlock filters – Cookie Notices", url: "https://ublockorigin.github.io/uAssets/filters/annoyances-cookies.txt", category: .annoyances),
            makeNativeFilter(name: "EasyList – Cookie Notices", url: "https://ublockorigin.github.io/uAssets/thirdparties/easylist-cookies.txt", category: .annoyances),
            makeNativeFilter(name: "EasyList – Social Widgets", url: "https://ublockorigin.github.io/uAssets/thirdparties/easylist-social.txt", category: .annoyances),
            makeNativeFilter(name: "EasyList – Other Annoyances", url: "https://ublockorigin.github.io/uAssets/thirdparties/easylist-annoyances.txt", category: .annoyances),
            makeNativeFilter(name: "EasyList – Chat Widgets", url: "https://ublockorigin.github.io/uAssets/thirdparties/easylist-chat.txt", category: .annoyances),
            makeNativeFilter(name: "EasyList – Newsletter Notices", url: "https://ublockorigin.github.io/uAssets/thirdparties/easylist-newsletters.txt", category: .annoyances),
            makeNativeFilter(name: "EasyList – Notifications", url: "https://ublockorigin.github.io/uAssets/thirdparties/easylist-notifications.txt", category: .annoyances),
            makeNativeFilter(name: "EasyList – AI Widgets", url: "https://ublockorigin.github.io/uAssets/thirdparties/easylist-ai.txt", category: .annoyances),
            makeNativeFilter(name: "AdGuard/uBO – URL Tracking Protection", url: "https://ublockorigin.github.io/uAssets/filters/privacy-removeparam.txt", category: .privacy),
            makeNativeFilter(name: "Block Outsider Intrusion into LAN", url: "https://ublockorigin.github.io/uAssets/filters/lan-block.txt", category: .security),
            makeNativeFilter(name: "AdGuard – Ads", url: "https://filters.adtidy.org/extension/ublock/filters/2_without_easylist.txt", category: .ads),
            makeNativeFilter(name: "AdGuard – Cookie Notices", url: "https://filters.adtidy.org/extension/ublock/filters/18.txt", category: .annoyances),
            makeNativeFilter(name: "AdGuard – Social Widgets", url: "https://filters.adtidy.org/extension/ublock/filters/4.txt", category: .annoyances),
            makeNativeFilter(name: "AdGuard – Popup Overlays", url: "https://filters.adtidy.org/extension/ublock/filters/19.txt", category: .annoyances),
            makeNativeFilter(name: "AdGuard – Mobile App Banners", url: "https://filters.adtidy.org/extension/ublock/filters/20.txt", category: .annoyances),
            makeNativeFilter(name: "AdGuard – Other Annoyances", url: "https://filters.adtidy.org/extension/ublock/filters/21.txt", category: .annoyances),
            makeNativeFilter(name: "AdGuard – Widgets", url: "https://filters.adtidy.org/extension/ublock/filters/22.txt", category: .annoyances),
            makeNativeFilter(name: "uBlock filters – Experimental", url: "https://ublockorigin.github.io/uAssets/filters/experimental.txt", category: .experimental),
        ]

        filterLists.insert(contentsOf: nativeCore, at: 0)
        #if os(iOS)
            filterLists.insert(
                makeNativeFilter(name: "AdGuard – Mobile Ads", url: "https://filters.adtidy.org/extension/ublock/filters/11.txt", category: .ads),
                at: min(nativeCore.count, filterLists.count)
            )
        #endif

        for index in filterLists.indices {
            filterLists[index].isSelected = Self.recommendedFilterNames.contains(filterLists[index].name)
        }

        return filterLists
    }

    /// Creates the default set of filter lists
    private func createDefaultFilterLists() -> [FilterList] {
        var filterLists = [
            FilterList(
                id: UUID(), name: "Bypass Paywalls Clean Filter",
                url: URL(
                    string:
                        "https://bpc-filter-proxy.wmailrelayb8d890.workers.dev"
                )!, category: FilterListCategory.annoyances,
                description:
                    "Blocks paywall-related elements. Enable the corresponding userscript for best results."
            ),
        ]

        filterLists.append(contentsOf: [
            FilterList(
                id: UUID(), name: "ABPindo",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/ABPindo/indonesianadblockrules/master/subscriptions/abpindo.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Indonesian.",
                languages: ["id"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "ABPVN List",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn_ublock.txt"
                )!, category: .foreign, description: "Vietnamese adblock filter list.",
                languages: ["vi"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Adblock List for Finland",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/finnish-easylist-addition/finnish-easylist-addition/gh-pages/Finland_adb.txt"
                )!, category: .foreign, description: "Finnish ad blocking filter list.",
                languages: ["fi"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdBlockID",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/realodix/AdBlockID/main/dist/adblockid.adfl.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Indonesian.",
                languages: ["id"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "AdGuard Chinese filter",
                url: URL(
                    string:
                        "https://filters.adtidy.org/extension/ublock/filters/224.txt"
                )!, category: .foreign,
                description:
                    "Filter list for Chinese-language websites.",
                languages: ["zh"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Dutch filter",
                url: URL(
                    string:
                        "https://filters.adtidy.org/extension/ublock/filters/8.txt"
                )!, category: .foreign,
                description:
                    "Filter list for Dutch-language websites.",
                languages: ["nl"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard French filter",
                url: URL(
                    string:
                        "https://filters.adtidy.org/extension/ublock/filters/16.txt"
                )!, category: .foreign,
                description:
                    "Filter list for French-language websites.",
                languages: ["fr"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Japanese filter",
                url: URL(
                    string:
                        "https://filters.adtidy.org/extension/ublock/filters/7.txt"
                )!, category: .foreign,
                description: "Filter that enables ad blocking on websites in Japanese language.",
                languages: ["ja"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Spanish/Portuguese filter",
                url: URL(
                    string:
                        "https://filters.adtidy.org/extension/ublock/filters/9.txt"
                )!, category: .foreign,
                description:
                    "Filter list that specifically removes ads on websites in Spanish, Portuguese, and Brazilian Portuguese languages.",
                languages: ["es", "pt"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Turkish filter",
                url: URL(
                    string:
                        "https://filters.adtidy.org/extension/ublock/filters/13.txt"
                )!, category: .foreign,
                description:
                    "Filter list that specifically removes ads on websites in Turkish language.",
                languages: ["tr"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Ukrainian filter",
                url: URL(
                    string:
                        "https://filters.adtidy.org/extension/ublock/filters/23.txt"
                )!, category: .foreign,
                description: "Filter that enables ad blocking on websites in Ukrainian language.",
                languages: ["uk"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "Bulgarian list",
                url: URL(string: "https://stanev.org/abp/adblock_bg.txt")!, category: .foreign,
                description: "Additional filter list for websites in Bulgarian.", languages: ["bg"],
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "CJX's Annoyances List",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/cjx82630/cjxlist/master/cjx-annoyance.txt"
                )!, category: .foreign,
                description: "Supplement for EasyList China+EasyList and EasyPrivacy.",
                languages: ["zh"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "Dandelion Sprout's Nordic Filters",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianList.txt"
                )!, category: .foreign,
                description:
                    "This list covers websites for Norway, Denmark, Iceland, Danish territories, and the Sami indigenous population.",
                languages: ["no", "da", "is", "fo"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Dandelion Sprout's Serbo-Croatian List",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/SerboCroatianList.txt"
                )!, category: .foreign,
                description:
                    "A filter list for websites in Serbian, Montenegrin, Croatian, and Bosnian.",
                languages: ["sr", "hr"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Czech and Slovak",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/tomasko126/easylistczechandslovak/master/filters.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Czech and Slovak.",
                languages: ["cs", "sk"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Germany",
                url: URL(string: "https://easylist.to/easylistgermany/easylistgermany.txt")!,
                category: .foreign,
                description:
                    "Filter list for German-language websites.",
                languages: ["de"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "EasyList Hebrew",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/easylist/EasyListHebrew/master/EasyListHebrew.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Hebrew.", languages: ["he"],
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Italy",
                url: URL(string: "https://easylist-downloads.adblockplus.org/easylistitaly.txt")!,
                category: .foreign, description: "Additional filter list for websites in Italian.",
                languages: ["it"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Lithuania",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/EasyList-Lithuania/easylist_lithuania/master/easylistlithuania.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Lithuanian.",
                languages: ["lt"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Polish",
                url: URL(string: "https://easylist-downloads.adblockplus.org/easylistpolish.txt")!,
                category: .foreign, description: "Additional filter list for websites in Polish.",
                languages: ["pl"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "EasyList Spanish",
                url: URL(string: "https://easylist-downloads.adblockplus.org/easylistspanish.txt")!,
                category: .foreign, description: "Additional filter list for websites in Spanish.",
                languages: ["es"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "EasyList Thailand",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/easylist-thailand/easylist-thailand/master/subscription/easylist-thailand.txt"
                )!, category: .foreign, description: "Filter that blocks ads on Thai sites.",
                languages: ["th"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Estonian List", url: URL(string: "https://ubo-et.lepik.io/list.txt")!,
                category: .foreign, description: "Filter for ad blocking on Estonian sites.",
                languages: ["et"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "Frellwit's Swedish Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/lassekongo83/Frellwits-filter-lists/master/Frellwits-Swedish-Filter.txt"
                )!, category: .foreign,
                description:
                    "Filter that aims to remove regional Swedish ads, tracking, social media, annoyances, sponsored articles etc.",
                languages: ["sv"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Greek AdBlock Filter",
                url: URL(string: "https://www.void.gr/kargig/void-gr-filters.txt")!,
                category: .foreign, description: "Additional filter list for websites in Greek.",
                languages: ["el"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "Hungarian filter",
                url: URL(
                    string:
                        "https://cdn.jsdelivr.net/gh/hufilter/hufilter@gh-pages/hufilter-ublock.txt"
                )!, category: .foreign,
                description:
                    "Hufilter. Filter list that specifically removes ads on websites in the Hungarian language.",
                languages: ["hu"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Icelandic ABP List",
                url: URL(string: "https://raw.githubusercontent.com/brave/adblock-lists/master/custom/is.txt")!, category: .foreign,
                description: "Additional filter list for websites in Icelandic.", languages: ["is"],
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "IndianList",
                url: URL(string: "https://easylist-downloads.adblockplus.org/indianlist.txt")!,
                category: .foreign,
                description:
                    "Additional filter list for websites in Hindi, Tamil and other Dravidian and Indic languages.",
                languages: ["hi"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "KAD - Anti-Scam",
                url: URL(
                    string: "https://raw.githubusercontent.com/FiltersHeroes/KAD/master/KAD.txt")!,
                category: .foreign,
                description:
                    "Filter that protects against various types of scams in the Polish network, such as mass text messaging, fake online stores, etc.",
                languages: ["pl"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "Latvian List",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/Latvian-List/adblock-latvian/master/lists/latvian-list.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Latvian.", languages: ["lv"],
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "List-KR",
                url: URL(
                    string: "https://cdn.jsdelivr.net/npm/@list-kr/filterslists@latest/dist/filterslist-uBlockOrigin-classic.txt")!,
                category: .foreign,
                description:
                    "Filter list for Korean-language websites.",
                languages: ["ko"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Liste AR",
                url: URL(string: "https://easylist-downloads.adblockplus.org/Liste_AR.txt")!,
                category: .foreign, description: "Additional filter list for websites in Arabic.",
                languages: ["ar"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Macedonian adBlock Filters",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/DeepSpaceHarbor/Macedonian-adBlock-Filters/master/Filters"
                )!, category: .foreign,
                description: "Blocks ads and trackers on various Macedonian websites.",
                languages: ["mk"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "Official Polish filters for AdBlock, uBlock Origin & AdGuard",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/MajkiIT/polish-ads-filter/master/polish-adblock-filters/adblock.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Polish.", languages: ["pl"],
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Persian Blocker",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/MasterKia/PersianBlocker/main/PersianBlocker.txt"
                )!, category: .foreign,
                description: "Filter list for blocking ads and trackers on websites in Persian.",
                languages: ["fa", "tg", "ps"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Polish Annoyances Filters",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/PolishFiltersTeam/PolishAnnoyanceFilters/master/PPB.txt"
                )!, category: .foreign,
                description:
                    "Filter list that hides and blocks pop-ups, widgets, newsletters, push notifications, arrows, tagged internal links that are off-topic, and other irritating elements. Polish GDPR-Cookies Filters is already in it.",
                languages: ["pl"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Polish Anti Adblock Filters",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/olegwukr/polish-privacy-filters/master/anti-adblock.txt"
                )!, category: .foreign,
                description: "Official Polish filters against Adblock alerts.", languages: ["pl"],
                trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Polish Anti-Annoying Special Supplement",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/FiltersHeroes/PolishAntiAnnoyingSpecialSupplement/master/polish_rss_filters.txt"
                )!, category: .foreign,
                description:
                    "Filters that block and hide RSS elements and remnants of hidden newsletters combined with social elements on Polish websites.",
                languages: ["pl"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Polish GDPR-Cookies Filters",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/MajkiIT/polish-ads-filter/master/cookies_filters/adblock_cookies.txt"
                )!, category: .foreign, description: "Polish filter list for cookies blocking.",
                languages: ["pl"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Polish Social Filters",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/MajkiIT/polish-ads-filter/master/adblock_social_filters/adblock_social_list.txt"
                )!, category: .foreign,
                description: "Polish filter list for social widgets, popups, etc.",
                languages: ["pl"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "road-block light",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/tcptomato/ROad-Block/master/road-block-filters-light.txt"
                )!, category: .foreign, description: "Romanian ad blocking filter subscription.",
                languages: ["ro"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "ROList",
                url: URL(string: "https://www.zoso.ro/pages/rolist.txt")!, category: .foreign,
                description: "Additional filter list for websites in Romanian.", languages: ["ro"],
                trustLevel: "low"),
            FilterList(
                id: UUID(), name: "ROLIST2",
                url: URL(string: "https://www.zoso.ro/pages/rolist2.txt")!, category: .foreign,
                description:
                    "This is a complementary list for ROList with annoyances that are not necessarily banners. It is a very aggressive list and not recommended for beginners.",
                languages: ["ro"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "RU AdList",
                url: URL(string: "https://raw.githubusercontent.com/easylist/ruadlist/master/RuAdList-uBO.txt")!,
                category: .foreign, description: "Filter list for Russian-language websites.",
                languages: ["ru", "uk", "be", "kk", "tt", "uz"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "RU AdList: Counters",
                url: URL(string: "https://raw.githubusercontent.com/easylist/ruadlist/master/cntblock.txt")!,
                category: .foreign, description: "RU AdList supplement for trackers blocking.",
                languages: ["ru"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "Xfiles",
                url: URL(
                    string: "https://raw.githubusercontent.com/gioxx/xfiles/master/filtri.txt")!,
                category: .foreign, description: "Italian adblock filter list.", languages: ["it"],
                trustLevel: "low"),
            FilterList(
                id: UUID(), name: "xinggsf",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/xinggsf/Adblock-Plus-Rule/master/rule.txt"
                )!, category: .foreign,
                description:
                    "Blocks ads on the Chinese video platforms (MangoTV, DouYu and others).",
                languages: ["zh"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "YousList",
                url: URL(
                    string: "https://raw.githubusercontent.com/yous/YousList/master/youslist.txt")!,
                category: .foreign, description: "Filter that blocks ads on Korean sites.",
                languages: ["ko"], trustLevel: "high"),
        ])
        for index in filterLists.indices {
            filterLists[index].isSelected = Self.recommendedFilterNames.contains(filterLists[index].name)
        }

        return filterLists
    }

    /// Checks if a filter file exists locally
    func filterFileExists(_ filter: FilterList) -> Bool {
        guard let containerURL = getSharedContainerURL() else { return false }
        let fileURLs = [
            containerURL.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter)),
            containerURL.appendingPathComponent(ContentBlockerIncrementalCache.legacyLocalFilename(for: filter))
        ]
        return fileURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Gets the URL for the shared container
    func getSharedContainerURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value)
    }

    /// Reads the content of a filter list from the local file system
    func readLocalFilterContent(_ filter: FilterList) -> String? {
        guard let containerURL = getSharedContainerURL() else { return nil }
        let fileURLs = [
            containerURL.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: filter)),
            containerURL.appendingPathComponent(ContentBlockerIncrementalCache.legacyLocalFilename(for: filter))
        ]

        for fileURL in fileURLs {
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                return content
            }
        }

        Task {
            await ConcurrentLogManager.shared.error(
                .filterUpdate, "Failed to read filter content",
                metadata: ["filter": filter.name])
        }
        return nil
    }
}
