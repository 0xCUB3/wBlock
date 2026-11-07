import Foundation
import wBlockCoreService

@main struct CatalogTest {
    static func main() {
        func check(_ value: Bool, _ message: String) { if !value { fputs("FAIL: \(message)\n", stderr); exit(1) } }
        let safari = URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/2_optimized.txt")!
        let track = URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_17_TrackParam/filter.txt")!
        let safariMirrors = FilterListURLMirror.fallbackURLs(for: safari).map(\.absoluteString)
        check(safariMirrors.contains("https://filters.adtidy.org/extension/safari/filters/2_optimized.txt"), "adtidy mirror")
        check(safariMirrors.contains("https://cdn.jsdelivr.net/gh/AdguardTeam/FiltersRegistry@master/platforms/extension/safari/filters/2_optimized.txt"), "jsdelivr mirror")
        check(!safariMirrors.contains(where: { $0.contains("ios/filters") }), "no ios safari mirror")
        let mobile = URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/ios/filters/11_optimized.txt")!
        check(FilterListURLMirror.fallbackURLs(for: mobile).map(\.absoluteString) == [
            "https://filters.adtidy.org/ios/filters/11_optimized.txt",
            "https://cdn.jsdelivr.net/gh/AdguardTeam/FiltersRegistry@master/platforms/ios/filters/11_optimized.txt",
        ], "ios registry mirrors")
        for id in [17, 251] {
            let primary = URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/mac_v3/filters/\(id)_optimized.txt")!
            let cdn = URL(string: "https://filters.adtidy.org/mac_v3/filters/\(id)_optimized.txt")!
            let js = URL(string: "https://cdn.jsdelivr.net/gh/AdguardTeam/FiltersRegistry@master/platforms/mac_v3/filters/\(id)_optimized.txt")!
            check(FilterListURLMirror.fallbackURLs(for: primary) == [cdn, js], "mac_v3 mirror order and platform")
            check(FilterListURLMirror.fallbackURLs(for: cdn) == [primary, js], "mac_v3 CDN primary")
            check(FilterListURLMirror.allowsFallback(primary: primary, fallback: cdn), "mac_v3 adtidy allowed")
            let wrongPlatform = URL(string: "https://filters.adtidy.org/extension/safari/filters/\(id)_optimized.txt")!
            check(!FilterListURLMirror.allowsFallback(primary: primary, fallback: wrongPlatform), "mac_v3 cannot use Safari mirrors")
        }
        let nordic = URL(string: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianExperimentalList%20alternate%20versions/NorwegianExperimentalList.txt")!
        let nordicMirrors = FilterListURLMirror.fallbackURLs(for: nordic)
        check(nordicMirrors.contains(where: { $0.host == "cdn.jsdelivr.net" }), "Nordic jsdelivr fallback")
        check(nordicMirrors.contains(where: { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath.contains("NorwegianExperimentalList%20alternate%20versions") == true }), "Nordic path encoding")
        check(FilterListURLMirror.fallbackURLs(for: track).allSatisfy { $0.host == "cdn.jsdelivr.net" }, "filter 17 mirror")
        check(FilterListURLMirror.fallbackURLs(for: URL(string: "https://cdn.jsdelivr.net/gh/a/b@main/x.txt")!).isEmpty, "no duplicate jsdelivr")

        for filename in ["2.txt", "2_optimized.txt"] {
            let cdn = URL(string: "https://filters.adtidy.org/extension/safari/filters/\(filename)")!
            let registry = URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/\(filename)")!
            let js = URL(string: "https://cdn.jsdelivr.net/gh/AdguardTeam/FiltersRegistry@master/platforms/extension/safari/filters/\(filename)")!
            check(FilterListURLMirror.fallbackURLs(for: cdn) == [registry, js], "CDN primary keeps variant and order")
        }
        let mobileCDN = URL(string: "https://filters.adtidy.org/ios/filters/11_optimized.txt")!
        check(FilterListURLMirror.fallbackURLs(for: mobileCDN).first == mobile, "iOS CDN primary keeps platform")
        check(FilterListURLMirror.allowsFallback(primary: mobile, fallback: mobileCDN), "iOS registry can use iOS CDN")
        check(!FilterListURLMirror.allowsFallback(primary: safari, fallback: mobileCDN), "Safari never uses iOS mirror")
        let wrongList = URL(string: "https://cdn.jsdelivr.net/gh/AdguardTeam/FiltersRegistry@master/platforms/extension/safari/filters/3_optimized.txt")!
        check(!FilterListURLMirror.allowsFallback(primary: safari, fallback: wrongList), "mirror keeps list identity")
        check(FilterListURLMirror.fallbackURLs(for: URL(string: "https://filters.adtidy.org/unknown.txt")!).isEmpty, "unknown CDN path has no inferred mirror")
        // AdGuard's uBlock Origin builds fall back to the registry, and uAssets lists to uBO's mirrors (#1079).
        let ublockGerman = URL(string: "https://filters.adtidy.org/extension/ublock/filters/6.txt")!
        check(FilterListURLMirror.fallbackURLs(for: ublockGerman).map(\.absoluteString) == [
            "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/ublock/filters/6.txt",
            "https://cdn.jsdelivr.net/gh/AdguardTeam/FiltersRegistry@master/platforms/extension/ublock/filters/6.txt",
        ], "AdGuard uBO build mirrors")
        // uAssets lists fall back freshest first, uAssets sources before uAssetsCDN (#1087).
        let easyList = URL(string: "https://ublockorigin.github.io/uAssetsCDN/thirdparties/easylist.txt")!
        check(FilterListURLMirror.fallbackURLs(for: easyList).map(\.absoluteString) == [
            "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/thirdparties/easylist/easylist.txt",
            "https://ublockorigin.github.io/uAssets/thirdparties/easylist.txt",
            "https://raw.githubusercontent.com/uBlockOrigin/uAssetsCDN/main/thirdparties/easylist.txt",
            "https://ublockorigin.pages.dev/thirdparties/easylist.txt",
            "https://cdn.jsdelivr.net/gh/uBlockOrigin/uAssets@master/thirdparties/easylist/easylist.txt",
            "https://cdn.jsdelivr.net/gh/uBlockOrigin/uAssetsCDN@main/thirdparties/easylist.txt",
        ], "uAssets mirrors")
        let ads = URL(string: "https://ublockorigin.github.io/uAssetsCDN/filters/filters.min.txt")!
        check(FilterListURLMirror.fallbackURLs(for: ads).prefix(2).map(\.absoluteString) == [
            "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt",
            "https://ublockorigin.github.io/uAssets/filters/filters.txt",
        ], "uAssets sources have no .min builds")
        // Regional lists follow the uBO regional document's mirror order (#1087).
        check(FilterListURLMirror.fallbackURLs(for: URL(string: "https://ubo-et.lepik.io/list.txt")!).map(\.absoluteString) == [
            "https://raw.githubusercontent.com/sander85/uBO-et/main/list.txt",
            "https://cdn.jsdelivr.net/gh/sander85/uBO-et@main/list.txt",
        ], "Estonian List mirrors")
        let ruAdList = URL(string: "https://cdn.jsdelivr.net/gh/dimisa-RUAdList/RUAdListCDN@main/lists/ruadlist.ubo.min.txt")!
        check(FilterListURLMirror.fallbackURLs(for: ruAdList).first?.absoluteString
              == "https://raw.githubusercontent.com/easylist/ruadlist/master/RuAdList-uBO.txt", "RU AdList falls back to its source first")
        print("PASS")
    }
}
