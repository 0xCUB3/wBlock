import Foundation
import wBlockCoreService

/// Who keeps each built-in list going and where it lives (#955). Authors are
/// the people doing most of the work in the list's repository over the past
/// year (all-time when the repository has been quiet); lists run by a large
/// team name the team. These replace whatever the downloaded header says.
enum BuiltInFilterCredits {
    struct Credit {
        let author: String?
        let homepage: URL
    }

    static func credit(for filter: FilterList) -> Credit? {
        guard !filter.isCustom else { return nil }
        if filter.name.hasPrefix("AdGuard ") { return adGuard }
        return byName[filter.name]
    }

    private static func credit(_ author: String?, _ homepage: String) -> Credit {
        Credit(author: author, homepage: URL(string: homepage)!)
    }

    private static let adGuard = credit("AdGuard", "https://github.com/AdguardTeam/AdguardFilters")
    private static let hagezi = credit("hagezi", "https://github.com/hagezi/dns-blocklists")
    private static let dandelionSprout = credit("DandelionSprout, iam-py-test", "https://github.com/DandelionSprout/adfilt")

    private static let byName: [String: Credit] = [
        "HaGeZi Referral Allowlist": hagezi,
        "HaGeZi Multi Pro Mini": hagezi,
        "Actually Legitimate URL Shortener Tool": dandelionSprout,
        "Dandelion Sprout's Anti-Malware List": dandelionSprout,
        "Dandelion Sprout's Nordic Filters": dandelionSprout,
        "Dandelion Sprout's Serbo-Croatian List": dandelionSprout,
        "Stevo's AI Blocklist": credit("Stevoisiak", "https://github.com/Stevoisiak/Stevos-AI-Blocklist"),
        "Block Outsider Intrusion into LAN": credit("stephenhawk8054, Yuki2718", "https://github.com/uBlockOrigin/uAssets"),
        "Peter Lowe's Blocklist": credit("Peter Lowe", "https://pgl.yoyo.org/adservers/"),
        "Adblock Warning Removal List": credit("dimisa-RUAdList, smed79", "https://github.com/easylist/antiadblockfilters"),
        "EasyPrivacy": credit("ryanbr", "https://github.com/easylist/easylist"),
        "Bypass Paywalls Clean Filter": credit("magnolia1234", "https://gitflic.ru/project/magnolia1234/bypass-paywalls-clean-filters"),
        "ABPindo": credit("gmarcher", "https://github.com/ABPindo/indonesianadblockrules"),
        "ABPVN List": credit("hoang-rio", "https://github.com/abpvn/abpvn"),
        "Adblock List for Finland": credit("peace2000", "https://github.com/finnish-easylist-addition/finnish-easylist-addition"),
        "AdBlockID": credit("realodix", "https://github.com/realodix/AdBlockID"),
        "Bulgarian list": credit("Alex Stanev", "https://stanev.org/abp"),
        "EasyList Czech and Slovak": credit("sebm253", "https://github.com/tomasko126/easylistczechandslovak"),
        "EasyList Hebrew": credit("Hebrew-uBO-User", "https://github.com/easylist/EasyListHebrew"),
        "EasyList Italy": credit("Khrin", "https://github.com/easylist/easylistitaly"),
        "EasyList Lithuania": credit("DandelionSprout, iibett", "https://github.com/EasyList-Lithuania/easylist_lithuania"),
        "EasyList Thailand": credit("gluons", "https://github.com/easylist-thailand/easylist-thailand"),
        "Estonian List": credit("sander85", "https://github.com/sander85/uBO-et"),
        "Frellwit's Swedish Filter": credit("lassekongo83", "https://github.com/lassekongo83/Frellwits-filter-lists"),
        "Greek AdBlock Filter": credit("kargig", "https://github.com/kargig/greek-adblockplus-filter"),
        "Hungarian filter": credit("babfozelek, scripthunter7", "https://github.com/hufilter/hufilter"),
        "Icelandic ABP List": credit(nil, "https://adblock.gardar.net"),
        "IndianList": credit("indianfilterlist, mediumkreation", "https://github.com/mediumkreation/IndianList"),
        "KAD - Anti-Scam": credit("krystian3w", "https://github.com/FiltersHeroes/KAD"),
        "Latvian List": credit("anonymous74100", "https://github.com/Latvian-List/adblock-latvian"),
        "filterslists-KO": credit("piquark6046", "https://github.com/FilteringDev/filterslists-KO"),
        "Liste AR": credit("smed79", "https://github.com/easylist/listear"),
        "Macedonian adBlock Filters": credit("DeepSpaceHarbor", "https://github.com/RandomAdversary/Macedonian-adBlock-Filters"),
        "Official Polish filters for AdBlock, uBlock Origin & AdGuard": credit("MajkiIT, krystian3w", "https://github.com/MajkiIT/polish-ads-filter"),
        "road-block light": credit("mapx-", "https://github.com/tcptomato/ROad-Block"),
    ]
}
