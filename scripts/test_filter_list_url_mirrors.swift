import Foundation
import wBlockCoreService

@main struct MirrorTest {
    static func main() {
        func check(_ value: Bool, _ message: String) { if !value { fputs("FAIL: \(message)\n", stderr); exit(1) } }
        let safari = URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/refs/heads/master/platforms/extension/safari/filters/2_optimized.txt")!
        let mirrors = FilterListURLMirror.fallbackURLs(for: safari).map(\.absoluteString)
        check(mirrors.contains("https://filters.adtidy.org/extension/safari/filters/2_optimized.txt"), "adtidy")
        check(mirrors.contains("https://cdn.jsdelivr.net/gh/AdguardTeam/FiltersRegistry@master/platforms/extension/safari/filters/2_optimized.txt"), "jsdelivr ref")
        check(!mirrors.contains(where: { $0.contains("ios/filters") }), "no ios safari mirror")
        let nordic = URL(string: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianExperimentalList%20alternate%20versions/NorwegianExperimentalList.txt")!
        let nordicMirrors = FilterListURLMirror.fallbackURLs(for: nordic)
        check(nordicMirrors.contains(where: { $0.host == "cdn.jsdelivr.net" }), "Nordic jsdelivr fallback")
        check(nordicMirrors.contains(where: { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath.contains("NorwegianExperimentalList%20alternate%20versions") == true }), "Nordic path encoding")

        let track = URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_17_TrackParam/filter.txt")!
        check(FilterListURLMirror.fallbackURLs(for: track).allSatisfy { $0.host == "cdn.jsdelivr.net" }, "filter 17")
        check(FilterListURLMirror.fallbackURLs(for: URL(string: "https://cdn.jsdelivr.net/gh/a/b@main/x.txt")!).isEmpty, "no duplicate jsdelivr")
        print("PASS")
    }
}
