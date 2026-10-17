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
        print("PASS")
    }
}
