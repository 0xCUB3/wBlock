import Foundation

/// Fallback endpoints derived from a built-in list's primary URL.
public enum FilterListURLMirror {
    public static func allowsFallback(primary: URL, fallback: URL) -> Bool {
        // A mirror must keep the same platform, list, and optimized/full variant.
        if let source = registryPath(for: primary), let mirror = registryPath(for: fallback), source != mirror {
            return false
        }
        guard fallback.host?.lowercased() == "filters.adtidy.org" else { return true }
        let primaryPath = primary.path.lowercased()
        let fallbackPath = fallback.path.lowercased()
        if primaryPath.contains("filter_17_trackparam")
            || (primaryPath.contains("/extension/safari/filters/") && primaryPath.contains("/17_")) {
            return false
        }
        let isSafariPrimary = primaryPath.contains("/platforms/extension/safari/filters/")
            || (primary.host?.lowercased() == "filters.adtidy.org" && primaryPath.hasPrefix("/extension/safari/filters/"))
        return !(isSafariPrimary && fallbackPath.contains("/ios/filters/"))
    }

    private static func registryPath(for url: URL) -> String? {
        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        if host == "filters.adtidy.org" {
            return ["/extension/safari/filters/", "/extension/ublock/filters/", "/ios/filters/", "/mac_v3/filters/"]
                .contains { path.hasPrefix($0) } ? path : nil
        }
        guard (host == "raw.githubusercontent.com" && path.hasPrefix("/adguardteam/filtersregistry/"))
            || (host == "cdn.jsdelivr.net" && path.hasPrefix("/gh/adguardteam/filtersregistry@")),
              let range = path.range(of: "/platforms") else { return nil }
        return String(path[range.upperBound...])
    }

    /// AdGuard's ID for a list at any registry or CDN address, such as 11 for
    /// .../ios/filters/11_optimized.txt, whatever the platform.
    public static func adGuardFilterID(for url: URL) -> Int? {
        if let path = registryPath(for: url) {
            return path.split(separator: "/").last.flatMap { Int($0.prefix { $0.isNumber }) }
        }
        // The registry's source tree: .../filters/filter_11_Mobile/filter.txt.
        guard url.host?.lowercased() == "raw.githubusercontent.com",
              url.path.lowercased().hasPrefix("/adguardteam/filtersregistry/") else { return nil }
        return url.pathComponents.lazy.compactMap { component -> Int? in
            guard component.hasPrefix("filter_") else { return nil }
            let digits = component.dropFirst("filter_".count).prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int(digits)
        }.first
    }

    /// R2 public bucket for the Bypass Paywalls Clean list; the worker serves the
    /// same object through its edge cache if the bucket URL ever fails.
    static let bpcBucketURL = URL(string: "https://pub-d303b9085c0b41b5aa749fc74609d4d9.r2.dev/bpc-paywall-filter.txt")!
    static let bpcWorkerURL = URL(string: "https://bpc-filter-proxy.wmailrelayb8d890.workers.dev")!

    /// Every copy of a uAssetsCDN list, freshest first (#1087): the uAssets
    /// sources, then uAssetsCDN on GitHub, its Pages and Cloudflare mirrors,
    /// and jsDelivr for each. uAssets has no `.min` builds and keeps EasyList's
    /// lists under thirdparties/easylist/. Its sources keep their `!#include`
    /// lines, which resolve against the copy that served them.
    private static func uAssetsMirrors(for url: URL) -> [URL]? {
        let host = url.host?.lowercased() ?? "", path = url.path
        let cdnPrefixes = [("ublockorigin.github.io", "/uAssetsCDN/"), ("ublockorigin.pages.dev", "/"),
                           ("cdn.jsdelivr.net", "/gh/uBlockOrigin/uAssetsCDN@main/"),
                           ("raw.githubusercontent.com", "/uBlockOrigin/uAssetsCDN/main/")]
        guard let prefix = cdnPrefixes.first(where: { host == $0.0 && path.hasPrefix($0.1) })?.1 else { return nil }
        let file = String(path.dropFirst(prefix.count))
        let source = file.replacingOccurrences(of: ".min.txt", with: ".txt")
        let repoSource = source.hasPrefix("thirdparties/")
            ? "thirdparties/easylist/" + source.dropFirst("thirdparties/".count) : source
        return [
            "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/" + repoSource,
            "https://ublockorigin.github.io/uAssets/" + source,
            "https://raw.githubusercontent.com/uBlockOrigin/uAssetsCDN/main/" + file,
            "https://ublockorigin.github.io/uAssetsCDN/" + file,
            "https://ublockorigin.pages.dev/" + file,
            "https://cdn.jsdelivr.net/gh/uBlockOrigin/uAssets@master/" + repoSource,
            "https://cdn.jsdelivr.net/gh/uBlockOrigin/uAssetsCDN@main/" + file,
        ].compactMap(URL.init(string:)).filter { $0 != url }
    }

    /// Regional lists' mirrors in the order the uBO regional list document
    /// gives them, freshest first (#1087). AdGuard's builds derive theirs below.
    private static let regionalFallbacks: [String: [String]] = [
        // Adblock List for Albania
        "https://raw.githubusercontent.com/AnXh3L0/blocklist/master/albanian-easylist-addition/Albania.txt": [
            "https://cdn.jsdelivr.net/gh/AnXh3L0/blocklist@master/albanian-easylist-addition/Albania.txt",
        ],
        // Liste AR
        "https://easylist-downloads.adblockplus.org/Liste_AR.txt": [
            "https://raw.githubusercontent.com/easylist/listear/master/Liste_AR.txt",
            "https://cdn.jsdelivr.net/gh/easylist/listear@master/Liste_AR.txt",
        ],
        // Bulgarian list
        "https://stanev.org/abp/adblock_bg.txt": [
            "https://raw.githubusercontent.com/RealEnder/adblockbg/master/adblockbg.txt",
            "https://easylist-downloads.adblockplus.org/bulgarian_list.txt",
            "https://cdn.jsdelivr.net/gh/RealEnder/adblockbg@master/adblockbg.txt",
        ],
        // EasyList Czech and Slovak
        "https://raw.githubusercontent.com/tomasko126/easylistczechandslovak/master/filters.txt": [
            "https://easylist-downloads.adblockplus.org/easylistczechslovak.txt",
            "https://cdn.jsdelivr.net/gh/tomasko126/easylistczechandslovak@master/filters.txt",
        ],
        // Raajje AdList
        "https://raw.githubusercontent.com/lonum1rus/Raajje-AdList/master/filter.txt": [
            "https://cdn.jsdelivr.net/gh/lonum1rus/Raajje-AdList@master/filter.txt",
        ],
        // Estonian List
        "https://ubo-et.lepik.io/list.txt": [
            "https://raw.githubusercontent.com/sander85/uBO-et/main/list.txt",
            "https://cdn.jsdelivr.net/gh/sander85/uBO-et@main/list.txt",
        ],
        // Adblock List for Finland
        "https://raw.githubusercontent.com/finnish-easylist-addition/finnish-easylist-addition/gh-pages/Finland_adb.txt": [
            "https://raw.githubusercontent.com/finnish-easylist-addition/finnish-easylist-addition/master/Finland_adb.txt",
            "https://cdn.jsdelivr.net/gh/finnish-easylist-addition/finnish-easylist-addition@master/Finland_adb.txt",
            "https://cdn.jsdelivr.net/gh/finnish-easylist-addition/finnish-easylist-addition@gh-pages/Finland_adb.txt",
        ],
        // Greek AdBlock Filter
        "https://www.void.gr/kargig/void-gr-filters.txt": [
            "https://raw.githubusercontent.com/kargig/greek-adblockplus-filter/master/void-gr-filters.txt",
            "https://cdn.jsdelivr.net/gh/kargig/greek-adblockplus-filter@master/void-gr-filters.txt",
        ],
        // EasyList Hebrew
        "https://raw.githubusercontent.com/easylist/EasyListHebrew/master/EasyListHebrew.txt": [
            "https://easylist-downloads.adblockplus.org/israellist.txt",
            "https://cdn.jsdelivr.net/gh/easylist/EasyListHebrew@master/EasyListHebrew.txt",
        ],
        // Hungarian filter
        "https://cdn.jsdelivr.net/gh/hufilter/hufilter@gh-pages/hufilter-ublock.txt": [
            "https://raw.githubusercontent.com/hufilter/hufilter/gh-pages/hufilter-ublock.txt",
            "https://filters.hufilter.hu/hufilter-ublock.txt",
        ],
        // Icelandic ABP List
        "https://raw.githubusercontent.com/brave/adblock-lists/master/custom/is.txt": [
            "https://cdn.jsdelivr.net/gh/brave/adblock-lists@master/custom/is.txt",
        ],
        // ABPindo
        "https://raw.githubusercontent.com/ABPindo/indonesianadblockrules/master/subscriptions/abpindo.txt": [
            "https://gitlab.com/ABPindo/indonesianadblockrules/-/raw/master/subscriptions/abpindo.txt",
            "https://easylist-downloads.adblockplus.org/abpindo.txt",
            "https://cdn.jsdelivr.net/gh/ABPindo/indonesianadblockrules@master/subscriptions/abpindo.txt",
        ],
        // AdBlockID
        "https://raw.githubusercontent.com/realodix/AdBlockID/main/dist/adblockid.adfl.txt": [
            "https://cdn.jsdelivr.net/gh/realodix/AdBlockID@main/dist/adblockid.adfl.txt",
        ],
        // Latvian List
        "https://raw.githubusercontent.com/Latvian-List/adblock-latvian/master/lists/latvian-list.txt": [
            "https://easylist-downloads.adblockplus.org/latvianlist.txt",
            "https://cdn.jsdelivr.net/gh/Latvian-List/adblock-latvian@master/lists/latvian-list.txt",
        ],
        // EasyList Lithuania
        "https://cdn.jsdelivr.net/gh/EasyList-Lithuania/easylist_lithuania@master/easylistlithuania.txt": [
            "https://raw.githubusercontent.com/EasyList-Lithuania/easylist_lithuania/master/easylistlithuania.txt",
            "https://easylist-downloads.adblockplus.org/easylistlithuania.txt",
        ],
        // Macedonian adBlock Filters
        "https://raw.githubusercontent.com/DeepSpaceHarbor/Macedonian-adBlock-Filters/master/Filters": [
            "https://cdn.jsdelivr.net/gh/DeepSpaceHarbor/Macedonian-adBlock-Filters@master/Filters",
        ],
        // Dandelion Sprout's Nordic Filters
        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianList.txt": [
            "https://easylist-downloads.adblockplus.org/dandelion_sprouts_nordic_filters.txt",
            "https://cdn.jsdelivr.net/gh/DandelionSprout/adfilt@master/NorwegianList.txt",
        ],
        // PersianBlockerNG
        "https://cdn.jsdelivr.net/gh/PersianBlocker/PersianBlocker@main/PersianBlocker.txt": [
            "https://raw.githubusercontent.com/PersianBlocker/PersianBlocker/main/PersianBlocker.txt",
        ],
        // KAD - Anti-Scam
        "https://raw.githubusercontent.com/FiltersHeroes/KAD/master/KAD.txt": [
            "https://filtersheroes.gitlab.io/AssetsMirror/KAD.txt",
            "https://cdn.jsdelivr.net/gh/FiltersHeroes/KAD@master/KAD.txt",
        ],
        // road-block light
        "https://raw.githubusercontent.com/tcptomato/ROad-Block/master/road-block-filters-light.txt": [
            "https://cdn.jsdelivr.net/gh/tcptomato/ROad-Block@master/road-block-filters-light.txt",
        ],
        // RU AdList
        "https://cdn.jsdelivr.net/gh/dimisa-RUAdList/RUAdListCDN@main/lists/ruadlist.ubo.min.txt": [
            "https://raw.githubusercontent.com/easylist/ruadlist/master/RuAdList-uBO.txt",
            "https://raw.githubusercontent.com/dimisa-RUAdList/RUAdListCDN/main/lists/ruadlist.ubo.min.txt",
            "https://cdn.jsdelivr.net/gh/easylist/ruadlist@master/RuAdList-uBO.txt",
        ],
        // Dandelion Sprout's Serbo-Croatian List
        "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/SerboCroatianList.txt": [
            "https://cdn.jsdelivr.net/gh/DandelionSprout/adfilt@master/SerboCroatianList.txt",
        ],
        // Slovenian List
        "https://raw.githubusercontent.com/betterwebleon/slovenian-list/master/filters.txt": [
            "https://cdn.jsdelivr.net/gh/betterwebleon/slovenian-list@master/filters.txt",
        ],
        // Frellwit's Swedish Filter
        "https://raw.githubusercontent.com/lassekongo83/Frellwits-filter-lists/swefilter/swefilter.min.txt": [
            "https://raw.githubusercontent.com/lassekongo83/Frellwits-filter-lists/master/Frellwits-Swedish-Filter.txt",
            "https://cdn.jsdelivr.net/gh/lassekongo83/Frellwits-filter-lists@master/Frellwits-Swedish-Filter.txt",
        ],
        // EasyList Thailand
        "https://raw.githubusercontent.com/easylist-thailand/easylist-thailand/master/subscription/easylist-thailand.txt": [
            "https://cdn.jsdelivr.net/gh/easylist-thailand/easylist-thailand@master/subscription/easylist-thailand.txt",
        ],
        // ABPVN List
        "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn_ublock.txt": [
            "https://cdn.jsdelivr.net/gh/abpvn/abpvn@master/filter/abpvn_ublock.txt",
            "https://abpvn.com/filter/abpvn-oC8lN4.txt?ublock",
        ],
    ]

    public static func fallbackURLs(for primary: URL) -> [URL] {
        guard primary.scheme?.lowercased() == "https",
              let host = primary.host?.lowercased() else { return [] }
        if primary == bpcBucketURL { return [bpcWorkerURL] }
        if let listed = regionalFallbacks[primary.absoluteString] { return listed.compactMap(URL.init(string:)) }
        if host == "filters.adtidy.org" {
            guard let path = registryPath(for: primary),
                  let registry = URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms\(path)") else { return [] }
            return ([registry] + fallbackURLs(for: registry)).filter {
                $0 != primary && allowsFallback(primary: primary, fallback: $0)
            }
        }
        if let uAssets = uAssetsMirrors(for: primary) { return uAssets }
        if host == "cdn.jsdelivr.net" { return [] }
        guard host == "raw.githubusercontent.com" else { return [] }
        // Use the encoded path: URL.path decodes spaces and other characters, which
        // would make the derived URL invalid when it is rebuilt from a string.
        guard let encodedPath = URLComponents(url: primary, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return [] }
        let parts = encodedPath.split(separator: "/").map(String.init)
        guard parts.count >= 4 else { return [] }
        let user = parts[0], repo = parts[1], ref = parts[2]
        let path = parts.dropFirst(3).joined(separator: "/")
        // List-KR has an intentional URL migration in the app catalog.
        if user.caseInsensitiveCompare("List-KR") == .orderedSame { return [] }
        let jsRef = ref == "refs" && parts.count >= 5 && parts[3] == "heads"
            ? (parts[4]) : ref
        let jsPath = (ref == "refs" && parts.count >= 5 && parts[3] == "heads")
            ? parts.dropFirst(5).joined(separator: "/") : path
        var jsDelivrComponents = URLComponents()
        jsDelivrComponents.scheme = "https"
        jsDelivrComponents.host = "cdn.jsdelivr.net"
        jsDelivrComponents.percentEncodedPath = "/gh/\(user)/\(repo)@\(jsRef)/\(jsPath)"
        guard let jsDelivr = jsDelivrComponents.url else { return [] }
        var result = [jsDelivr]
        // AdGuard publishes each registry platform at the same path on its own CDN.
        let platforms = ["platforms/extension/safari/filters/": "extension/safari/filters/",
                         "platforms/extension/ublock/filters/": "extension/ublock/filters/",
                         "platforms/ios/filters/": "ios/filters/",
                         "platforms/mac_v3/filters/": "mac_v3/filters/"]
        if user == "AdguardTeam" && repo == "FiltersRegistry",
           let (prefix, adtidyPath) = platforms.first(where: { jsPath.hasPrefix($0.key) }) {
            let filename = String(jsPath.dropFirst(prefix.count))
            // filter 17 is not published at AdGuard's Safari endpoint.
            if filename != "filter.txt" && filename != "filter_17_TrackParam.txt"
                && !(adtidyPath == "extension/safari/filters/" && filename.hasPrefix("17_")) {
                result.insert(URL(string: "https://filters.adtidy.org/\(adtidyPath)\(filename)")!, at: 0)
            }
        }
        var seen = Set<URL>()
        return result.filter {
            allowsFallback(primary: primary, fallback: $0) && seen.insert($0).inserted
        }
    }
}
