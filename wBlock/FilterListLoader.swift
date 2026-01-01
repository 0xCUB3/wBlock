//
//  FilterListLoader.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import Foundation
import wBlockCoreService

class FilterListLoader {
    private let logManager: ConcurrentLogManager
    private let customFilterListsKey = "customFilterLists"
    private let sharedContainerIdentifier = "group.skula.wBlock"
    private let filterURLMigrations: [String: URL] = [
        "https://raw.githubusercontent.com/List-KR/List-KR/refs/heads/master/filter-AdGuard-forward.txt":
            URL(string: "https://filters.adtidy.org/extension/safari/filters/227_optimized.txt")!,
        "https://raw.githubusercontent.com/List-KR/List-KR/master/filter-AdGuard-forward.txt": URL(
            string: "https://filters.adtidy.org/extension/safari/filters/227_optimized.txt")!,
    ]

    // Cache the defaults instance
    private let defaults: UserDefaults

    init(logManager: ConcurrentLogManager) {
        self.logManager = logManager
        self.defaults =
            UserDefaults(suiteName: GroupIdentifier.shared.value) ?? UserDefaults.standard
    }

    func checkAndCreateGroupFolder() {
        guard let containerURL = getSharedContainerURL() else {
            Task {
                await ConcurrentLogManager.shared.error(
                    .system, "Unable to access shared container")
            }
            return
        }

        if !FileManager.default.fileExists(atPath: containerURL.path) {
            do {
                try FileManager.default.createDirectory(
                    at: containerURL, withIntermediateDirectories: true, attributes: nil)
                Task {
                    await ConcurrentLogManager.shared.debug(
                        .system, "Created shared container directory")
                }
            } catch {
                Task {
                    await ConcurrentLogManager.shared.error(
                        .system, "Failed to create shared container directory",
                        metadata: ["error": "\(error)"])
                }
            }
        }
    }

    /// Loads filter lists from UserDefaults or creates default ones
    func loadFilterLists() -> [FilterList] {
        var filterLists: [FilterList] = []

        let defaultFilterLists = createDefaultFilterLists()

        if let data = defaults.data(forKey: "filterLists"),
            let savedFilterLists = try? JSONDecoder().decode([FilterList].self, from: data)
        {

            // Migrate any legacy URLs to their new locations
            let migratedSavedFilters = migrateFilterURLs(in: savedFilterLists)

            // Create a map of default filters by URL for quick lookup
            let defaultFiltersByURL = Dictionary(
                uniqueKeysWithValues: defaultFilterLists.map { ($0.url, $0) })

            // Update saved filters with default properties, preserving user settings
            for savedFilter in migratedSavedFilters {
                if let defaultFilter = defaultFiltersByURL[savedFilter.url] {
                    // Create updated filter with default properties but preserve user choices
                    let updatedFilter = FilterList(
                        id: savedFilter.id,  // Keep the original ID
                        name: defaultFilter.name,  // Use default name (may have been updated)
                        url: defaultFilter.url,  // Use default URL (may have been updated)
                        category: defaultFilter.category,  // Use default category
                        isSelected: savedFilter.isSelected,  // Preserve user's selection
                        description: defaultFilter.description,  // Use default description (may have been updated)
                        version: savedFilter.version,  // Keep version info
                        sourceRuleCount: savedFilter.sourceRuleCount,  // Keep rule count
                        lastUpdated: savedFilter.lastUpdated,
                        languages: defaultFilter.languages.isEmpty
                            ? savedFilter.languages : defaultFilter.languages,
                        trustLevel: defaultFilter.trustLevel ?? savedFilter.trustLevel,
                        etag: savedFilter.etag,
                        serverLastModified: savedFilter.serverLastModified
                    )
                    filterLists.append(updatedFilter)
                } else {
                    // Keep filters that aren't in defaults (like custom filters)
                    filterLists.append(savedFilter)
                }
            }

            // Add any new default filters that weren't in saved data
            let existingURLs = Set(migratedSavedFilters.map { $0.url })
            for defaultFilter in defaultFilterLists {
                if !existingURLs.contains(defaultFilter.url) {
                    filterLists.append(defaultFilter)
                }
            }

            // Migrate old AdGuard Annoyances Filter to new split filters
            filterLists = migrateOldAnnoyancesFilter(
                in: filterLists, defaultFilters: defaultFilterLists)
        } else {
            filterLists = defaultFilterLists
        }

        // Handle custom lists separately - these should always be preserved and updated
        let customLists = loadCustomFilterLists()

        // Remove any custom filters that are no longer in the custom list
        filterLists.removeAll { filter in
            filter.category == FilterListCategory.custom
                && !customLists.contains(where: { $0.url == filter.url })
        }

        // Add or update custom filters
        for customFilter in customLists {
            if let existingIndex = filterLists.firstIndex(where: { $0.url == customFilter.url }) {
                // Create updated custom filter with new data but preserve user settings
                let existingFilter = filterLists[existingIndex]
                let updatedCustomFilter = FilterList(
                    id: existingFilter.id,  // Keep the original ID
                    name: customFilter.name,  // Use custom filter name (may have been updated)
                    url: customFilter.url,  // Use custom filter URL
                    category: customFilter.category,  // Use custom filter category
                    isSelected: existingFilter.isSelected,  // Preserve user's selection
                    description: customFilter.description,  // Use custom filter description (may have been updated)
                    version: existingFilter.version,  // Keep version info
                    sourceRuleCount: existingFilter.sourceRuleCount,
                    lastUpdated: existingFilter.lastUpdated,
                    languages: existingFilter.languages,
                    trustLevel: existingFilter.trustLevel,
                    etag: existingFilter.etag,
                    serverLastModified: existingFilter.serverLastModified
                )
                filterLists[existingIndex] = updatedCustomFilter
            } else {
                // Add new custom filter
                filterLists.append(customFilter)
            }
        }

        return filterLists
    }

    /// Updates any known legacy filter URLs to their current endpoints.
    func migrateFilterURLs(in filters: [FilterList]) -> [FilterList] {
        filters.map { filter in
            guard let newURL = filterURLMigrations[filter.url.absoluteString] else {
                return filter
            }

            var migratedFilter = filter
            migratedFilter.url = newURL
            migratedFilter.etag = nil
            migratedFilter.serverLastModified = nil
            return migratedFilter
        }
    }

    private func migrateOldAnnoyancesFilter(in filters: [FilterList], defaultFilters: [FilterList])
        -> [FilterList]
    {
        var result = filters

        // Migration 1: Replace old combined AdGuard Annoyances Filter (14) with split filters (18-22)
        if let oldFilterIndex = result.firstIndex(where: {
            $0.url.absoluteString.contains("14_optimized.txt")
        }) {
            let wasSelected = result[oldFilterIndex].isSelected
            result.remove(at: oldFilterIndex)

            let newFilterURLs = [
                "18_optimized.txt", "19_optimized.txt", "20_optimized.txt", "21_optimized.txt",
                "22_optimized.txt",
            ]
            for newURL in newFilterURLs {
                if !result.contains(where: { $0.url.absoluteString.contains(newURL) }),
                    let defaultFilter = defaultFilters.first(where: {
                        $0.url.absoluteString.contains(newURL)
                    })
                {
                    var newFilter = defaultFilter
                    newFilter.isSelected = wasSelected
                    result.append(newFilter)
                }
            }
        }

        // Migration 2: Remove duplicate iOS-specific "AdGuard Mobile App Banners" filter
        // (filters.adtidy.org/ios/filters/20_optimized.txt) if the main one exists
        // (FiltersRegistry/.../20_optimized.txt)
        let hasMainMobileAppBanners = result.contains(where: {
            $0.url.absoluteString.contains("FiltersRegistry")
                && $0.url.absoluteString.contains("20_optimized.txt")
        })
        if hasMainMobileAppBanners {
            result.removeAll(where: {
                $0.url.absoluteString.contains("filters.adtidy.org/ios/filters/20_optimized.txt")
            })
        }

        return result
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
                description: "Comprehensive ad-blocking rules by AdGuard."),
            FilterList(
                id: UUID(), name: "AdGuard Tracking Protection Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/3_optimized.txt"
                )!, category: FilterListCategory.privacy, isSelected: true,
                description: "Blocks online tracking and web analytics systems."),
            FilterList(
                id: UUID(), name: "AdGuard Cookie Notices",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/18_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description: "Blocks cookie consent notices on web pages."),
            FilterList(
                id: UUID(), name: "AdGuard Popups",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/19_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description:
                    "Blocks promotional pop-ups, newsletter sign-ups, and notification requests."),
            FilterList(
                id: UUID(), name: "AdGuard Mobile App Banners",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/20_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description: "Blocks banners promoting mobile app downloads."),
            FilterList(
                id: UUID(), name: "AdGuard Other Annoyances",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/21_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description:
                    "Blocks miscellaneous irritating elements not covered by other filters."),
            FilterList(
                id: UUID(), name: "AdGuard Widgets",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/22_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description: "Blocks third-party widgets, chat assistants, and support widgets."),
            FilterList(
                id: UUID(), name: "AdGuard Social Media Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/4_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description: "Blocks social media widgets and buttons."),
            FilterList(
                id: UUID(), name: "Fanboy's Annoyances Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/122_optimized.txt"
                )!, category: FilterListCategory.annoyances,
                description: "Hides in-page pop-ups, banners, and other unwanted page elements."),
            FilterList(
                id: UUID(), name: "Fanboy's Social Blocking List",
                url: URL(string: "https://easylist.to/easylist/fanboy-social.txt")!,
                category: FilterListCategory.annoyances,
                description: "Blocks social media content on webpages."),
            FilterList(
                id: UUID(), name: "Fanboy's Anti-AI Suggestions",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/easylist/easylist/refs/heads/master/fanboy-addon/fanboy_ai_suggestions.txt"
                )!, category: FilterListCategory.annoyances,
                description:
                    "Blocks AI-generated suggestions and recommendations on search engines and websites."
            ),
            FilterList(
                id: UUID(), name: "Online Security Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/208_optimized.txt"
                )!, category: FilterListCategory.security, isSelected: true,
                description:
                    "Protects against suspicious URLs, phishing sites, and unwanted software."),
            FilterList(
                id: UUID(), name: "Peter Lowe's Blocklist",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/204_optimized.txt"
                )!, category: FilterListCategory.annoyances, isSelected: true,
                description: "Blocks ads and tracking servers to enhance privacy."),
            FilterList(
                id: UUID(), name: "d3Host List by d3ward",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/d3ward/toolz/master/src/d3host.adblock")!,
                category: FilterListCategory.annoyances, isSelected: true,
                description: "Comprehensive block list for ads and trackers."),
            FilterList(
                id: UUID(), name: "Anti-Adblock List",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/207_optimized.txt"
                )!, category: FilterListCategory.annoyances, isSelected: true,
                description: "Bypasses Anti-Adblock scripts used on some websites."),
            FilterList(
                id: UUID(), name: "Bypass Paywalls Clean Filter",
                url: URL(
                    string:
                        "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters/blob/raw?file=bpc-paywall-filter.txt"
                )!, category: FilterListCategory.annoyances,
                description:
                    "Blocks paywall-related elements. Enable the corresponding userscript for best results."
            ),
            FilterList(
                id: UUID(), name: "AdGuard Experimental Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/5_optimized.txt"
                )!, category: FilterListCategory.experimental,
                description: "Contains new rules and fixes not yet included in other filters."),
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
                        "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn_adguard.txt"
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
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/224_optimized.txt"
                )!, category: .foreign,
                description:
                    "EasyList China + AdGuard Chinese filter. Filter list that specifically removes ads on websites in Chinese language.",
                languages: ["zh"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Dutch filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/8_optimized.txt"
                )!, category: .foreign,
                description:
                    "EasyList Dutch + AdGuard Dutch filter. Filter list that specifically removes ads on websites in Dutch language.",
                languages: ["nl"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard French filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/16_optimized.txt"
                )!, category: .foreign,
                description:
                    "Liste FR + AdGuard French filter. Filter list that specifically removes ads on websites in French language.",
                languages: ["fr"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard German filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/6_optimized.txt"
                )!, category: .foreign,
                description:
                    "EasyList Germany + AdGuard German filter. Filter list that specifically removes ads on websites in German language.",
                languages: ["de"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Japanese filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/7_optimized.txt"
                )!, category: .foreign,
                description: "Filter that enables ad blocking on websites in Japanese language.",
                languages: ["ja"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Russian filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/1_optimized.txt"
                )!, category: .foreign,
                description: "Filter that enables ad blocking on websites in Russian language.",
                languages: ["ru"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Spanish/Portuguese filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/9_optimized.txt"
                )!, category: .foreign,
                description:
                    "Filter list that specifically removes ads on websites in Spanish, Portuguese, and Brazilian Portuguese languages.",
                languages: ["es", "pt"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Turkish filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/13_optimized.txt"
                )!, category: .foreign,
                description:
                    "Filter list that specifically removes ads on websites in Turkish language.",
                languages: ["tr"], trustLevel: "full"),
            FilterList(
                id: UUID(), name: "AdGuard Ukrainian filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/23_optimized.txt"
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
                        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianExperimentalList%20alternate%20versions/NordicFiltersAdGuard.txt"
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
                id: UUID(), name: "EasyList China",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/easylist/easylistchina/master/easylistchina.txt"
                )!, category: .foreign,
                description:
                    "Additional filter list for websites in Chinese. Already included in AdGuard Chinese filter.",
                languages: ["zh"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Czech and Slovak",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/tomasko126/easylistczechandslovak/master/filters.txt"
                )!, category: .foreign,
                description: "Additional filter list for websites in Czech and Slovak.",
                languages: ["cs", "sk"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "EasyList Dutch",
                url: URL(string: "https://easylist-downloads.adblockplus.org/easylistdutch.txt")!,
                category: .foreign,
                description:
                    "Additional filter list for websites in Dutch. Already included in AdGuard Dutch filter.",
                languages: ["nl"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "EasyList Germany",
                url: URL(string: "https://easylist.to/easylistgermany/easylistgermany.txt")!,
                category: .foreign,
                description:
                    "Additional filter list for websites in German. Already included in AdGuard German filter.",
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
                id: UUID(), name: "EasyList Portuguese",
                url: URL(
                    string: "https://easylist-downloads.adblockplus.org/easylistportuguese.txt")!,
                category: .foreign,
                description: "Additional filter list for websites in Spanish and Portuguese.",
                languages: ["es", "pt"], trustLevel: "low"),
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
                id: UUID(), name: "Estonian List", url: URL(string: "https://adblock.ee/list.txt")!,
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
                        "https://cdn.jsdelivr.net/gh/hufilter/hufilter@gh-pages/hufilter-adguard.txt"
                )!, category: .foreign,
                description:
                    "Hufilter. Filter list that specifically removes ads on websites in the Hungarian language.",
                languages: ["hu"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Icelandic ABP List",
                url: URL(string: "https://adblock.gardar.net/is.abp.txt")!, category: .foreign,
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
                    string: "https://filters.adtidy.org/extension/safari/filters/227_optimized.txt")!,
                category: .foreign,
                description:
                    "Filter that removes ads and various scripts from websites with Korean content. Combined and augmented with AdGuard-specific rules for enhanced filtering. This filter is expected to be used alongside with AdGuard Base filter.",
                languages: ["ko"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Liste AR",
                url: URL(string: "https://easylist-downloads.adblockplus.org/Liste_AR.txt")!,
                category: .foreign, description: "Additional filter list for websites in Arabic.",
                languages: ["ar"], trustLevel: "high"),
            FilterList(
                id: UUID(), name: "Liste FR",
                url: URL(string: "https://easylist-downloads.adblockplus.org/liste_fr.txt")!,
                category: .foreign,
                description:
                    "Additional filter list for websites in French. Already included in AdGuard French filter.",
                languages: ["fr"], trustLevel: "low"),
            FilterList(
                id: UUID(), name: "Macedonian adBlock Filters",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/RandomAdversary/Macedonian-adBlock-Filters/master/Filters"
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
                id: UUID(), name: "RU AdList: Counters",
                url: URL(string: "https://easylist-downloads.adblockplus.org/cntblock.txt")!,
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
        filterLists.append(
            FilterList(
                id: UUID(), name: "EasyPrivacy",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/118_optimized.txt"
                )!, category: FilterListCategory.privacy, isSelected: true,
                description:
                    "Blocks tracking scripts, web beacons, and other privacy-invasive elements."))
        filterLists.append(
            FilterList(
                id: UUID(), name: "AdGuard URL Tracking Filter",
                url: URL(
                    string:
                        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_17_TrackParam/filter.txt"
                )!, category: FilterListCategory.privacy, isSelected: false,
                description:
                    "Removes tracking parameters from URLs (utm_source, fbclid, gclid, etc.) to enhance privacy."
            ))

        #if os(iOS)
            filterLists.append(
                FilterList(
                    id: UUID(), name: "AdGuard Mobile Filter",
                    url: URL(
                        string:
                            "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_11_Mobile/filter.txt"
                    )!, category: FilterListCategory.ads, isSelected: true,
                    description: "Optimized for mobile ad blocking. Recommended for iOS/iPadOS."))
        #endif

        #if os(macOS)
            // macOS-only filters too large for iOS
            filterLists.append(
                FilterList(
                    id: UUID(), name: "Hagezi Pro Mini",
                    url: URL(
                        string:
                            "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.mini.txt"
                    )!, category: FilterListCategory.annoyances, isSelected: true,
                    description:
                        "Extensive blocklist targeting ads, trackers, and other unwanted content."))
        #endif

        // Set default selections for recommended filters
        #if os(macOS)
            let recommendedFilters = [
                "AdGuard Base Filter",
                "AdGuard Tracking Protection Filter",
                "EasyPrivacy",
                "AdGuard URL Tracking Filter",
                "Online Security Filter",
                "d3Host List by d3ward",
                "AdGuard Cookie Notices",
                "AdGuard Popups",
                "AdGuard Mobile App Banners",
                "AdGuard Other Annoyances",
                "AdGuard Widgets",
                "Anti-Adblock List",
            ]
        #else
            let recommendedFilters = [
                "AdGuard Base Filter",
                "AdGuard Tracking Protection Filter",
                "EasyPrivacy",
                "AdGuard URL Tracking Filter",
                "Online Security Filter",
                "d3Host List by d3ward",
                "AdGuard Cookie Notices",
                "AdGuard Popups",
                "AdGuard Mobile App Banners",
                "AdGuard Other Annoyances",
                "AdGuard Widgets",
                "Anti-Adblock List",
                "AdGuard Mobile Filter",  // Added for iOS/iPadOS
            ]
        #endif

        for index in filterLists.indices {
            filterLists[index].isSelected = recommendedFilters.contains(filterLists[index].name)
        }

        return filterLists
    }

    /// Saves filter lists to UserDefaults
    func saveFilterLists(_ filterLists: [FilterList]) {
        // Separate default and custom lists before saving
        let defaultLists = filterLists.filter { $0.category != FilterListCategory.custom }
        let customLists = filterLists.filter { $0.category == FilterListCategory.custom }

        if let data = try? JSONEncoder().encode(defaultLists) {
            defaults.set(data, forKey: "filterLists")
        } else {
            Task {
                await ConcurrentLogManager.shared.error(
                    .system, "Failed to encode default filterLists")
            }
        }

        // Save custom lists separately
        saveCustomFilterLists(customLists)

        // Save the selected state
        saveSelectedState(for: filterLists)
    }

    /// Loads selected state for filter lists from UserDefaults
    func loadSelectedState(for filterLists: inout [FilterList]) {
        for index in filterLists.indices {
            let key = "filter_selected_\(filterLists[index].id.uuidString)"
            filterLists[index].isSelected =
                defaults.object(forKey: key) as? Bool ?? filterLists[index].isSelected
        }
    }

    /// Saves selected state for filter lists to UserDefaults
    func saveSelectedState(for filterLists: [FilterList]) {
        Task.detached(priority: .background) { [defaults] in
            for filter in filterLists {
                let key = "filter_selected_\(filter.id.uuidString)"
                defaults.set(filter.isSelected, forKey: key)
            }
        }
    }

    /// Loads custom filter lists from UserDefaults
    func loadCustomFilterLists() -> [FilterList] {
        if let data = defaults.data(forKey: customFilterListsKey),
            let customLists = try? JSONDecoder().decode([FilterList].self, from: data)
        {
            return customLists
        }
        return []
    }

    /// Saves custom filter lists to UserDefaults
    func saveCustomFilterLists(_ customFilterLists: [FilterList]) {
        Task.detached(priority: .background) { [defaults, customFilterListsKey] in
            if let data = try? JSONEncoder().encode(customFilterLists) {
                defaults.set(data, forKey: customFilterListsKey)
            } else {
                await ConcurrentLogManager.shared.error(
                    .system, "Failed to encode customFilterLists")
            }
        }
    }

    /// Checks if a filter file exists locally
    func filterFileExists(_ filter: FilterList) -> Bool {
        guard let containerURL = getSharedContainerURL() else { return false }
        return FileManager.default.fileExists(
            atPath: containerURL.appendingPathComponent("\(filter.name).txt").path)
    }

    /// Gets the URL for the shared container
    func getSharedContainerURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: sharedContainerIdentifier)
    }

    /// Reads the content of a filter list from the local file system
    func readLocalFilterContent(_ filter: FilterList) -> String? {
        guard let containerURL = getSharedContainerURL() else { return nil }
        let fileURL = containerURL.appendingPathComponent("\(filter.name).txt")

        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            Task {
                await ConcurrentLogManager.shared.error(
                    .filterUpdate, "Failed to read filter content",
                    metadata: ["filter": filter.name, "error": "\(error)"])
            }
            return nil
        }
    }
}
