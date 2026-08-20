import Foundation
import wBlockCoreService

@main struct CatalogTest {
    static func main() {
        func check(_ value: Bool, _ message: String) { if !value { fputs("FAIL: \(message)\n", stderr); exit(1) } }
        let target = URL(string: "https://example.com/list.txt")!
        let old = URL(string: "https://github.com/old/list.txt")!
        let data = Data("""
        {"schemaVersion":1,"lists":[
          {"name":"List","url":"https://example.com/list.txt","fallbacks":["https://cdn.example/list.txt"],"replaceFrom":["https://github.com/old/list.txt"]},
          {"name":"Skipped","url":"https://not-built-in.example/list.txt","fallbacks":[],"replaceFrom":["https://github.com/ignored.txt"]},
          {"name":"Kept","url":"https://other.example/list.txt","fallbacks":[]}
        ]}
        """.utf8)
        let overlay = FilterCatalogOverlay.parse(data, defaultURLs: [target])
        check(overlay?.lists.count == 2, "invalid replacement target only skips entry")
        check(overlay?.fallbacks(for: FilterList(name: "List", url: target, category: .ads)).isEmpty == true, "untrusted overlay fallback stripped")
        let input = [FilterList(name: "List", url: old, category: .ads)]
        check(overlay?.applyReplacements(to: input, defaultURLs: [target]).first?.url == target, "replacement applied")

        let safari = URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters/2_optimized.txt")!
        let track = URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_17_TrackParam/filter.txt")!
        let forbiddenData = Data("""
        {"schemaVersion":1,"lists":[
          {"name":"Base","url":"\(safari.absoluteString)","fallbacks":["https://filters.adtidy.org/ios/filters/2.txt"]},
          {"name":"Track","url":"\(track.absoluteString)","fallbacks":["https://filters.adtidy.org/ios/filters/17.txt"]}
        ]}
        """.utf8)
        let forbidden = FilterCatalogOverlay.parse(forbiddenData, defaultURLs: [safari, track])!
        check(!forbidden.fallbacks(for: FilterList(name: "Base", url: safari, category: .ads)).contains { $0.path.contains("/ios/filters/") }, "ios fallback stripped")
        check(forbidden.fallbacks(for: FilterList(name: "Track", url: track, category: .ads)).allSatisfy { $0.host != "filters.adtidy.org" }, "filter 17 adtidy fallback stripped")

        let safariMirrors = FilterListURLMirror.fallbackURLs(for: safari).map(\.absoluteString)
        check(safariMirrors.contains("https://filters.adtidy.org/extension/safari/filters/2_optimized.txt"), "adtidy mirror")
        check(safariMirrors.contains("https://cdn.jsdelivr.net/gh/AdguardTeam/FiltersRegistry@master/platforms/extension/safari/filters/2_optimized.txt"), "jsdelivr mirror")
        check(!safariMirrors.contains(where: { $0.contains("ios/filters") }), "no ios safari mirror")
        let nordic = URL(string: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianExperimentalList%20alternate%20versions/NorwegianExperimentalList.txt")!
        let nordicMirrors = FilterListURLMirror.fallbackURLs(for: nordic)
        check(nordicMirrors.contains(where: { $0.host == "cdn.jsdelivr.net" }), "Nordic jsdelivr fallback")
        check(nordicMirrors.contains(where: { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath.contains("NorwegianExperimentalList%20alternate%20versions") == true }), "Nordic path encoding")
        check(FilterListURLMirror.fallbackURLs(for: track).allSatisfy { $0.host == "cdn.jsdelivr.net" }, "filter 17 mirror")
        check(FilterListURLMirror.fallbackURLs(for: URL(string: "https://cdn.jsdelivr.net/gh/a/b@main/x.txt")!).isEmpty, "no duplicate jsdelivr")

        let extraJs = "https://cdn.jsdelivr.net/gh/AdguardTeam/FiltersRegistry@master/platforms/extension/safari/filters/2.txt"
        let mixedJSON = """
        {"schemaVersion":1,"lists":[{"name":"AdGuard Base Filter","url":"\(safari.absoluteString)","fallbacks":["https://evil.example/x.txt","\(extraJs)"]}]}
        """
        let mixed = FilterCatalogOverlay.parse(Data(mixedJSON.utf8), defaultURLs: [safari])!
        let mixedFallbacks = mixed.fallbacks(for: FilterList(name: "AdGuard Base Filter", url: safari, category: .ads))
        check(!mixedFallbacks.contains { $0.host == "evil.example" }, "attacker overlay fallback stripped")
        check(mixedFallbacks.contains { $0.absoluteString == extraJs }, "trusted jsdelivr overlay fallback kept")
        let custom = FilterList(name: "AdGuard Base Filter", url: URL(string: "https://example.com/custom.txt")!, category: .ads, isCustom: true)
        check(!mixed.fallbacks(for: custom).contains { $0.host == "filters.adtidy.org" }, "custom list does not inherit built-in fallbacks")
        check(FilterCatalogRemote.fallbacks(for: custom) == FilterListURLMirror.fallbackURLs(for: custom.url), "custom remote fallbacks are mirrors only")

        let http = Data("{\"schemaVersion\":1,\"lists\":[{\"name\":\"bad\",\"url\":\"http://example.com/list.txt\"}]}".utf8)
        check(FilterCatalogOverlay.parse(http, defaultURLs: []) == nil, "http rejected")
        let empty = FilterCatalogOverlay.parse(Data("{\"schemaVersion\":1,\"lists\":[]}".utf8), defaultURLs: [])
        check(empty?.lists.isEmpty == true, "empty overlay")
        check(FilterCatalogOverlay.parse(Data("{\"schemaVersion\":2,\"lists\":[]}".utf8), defaultURLs: []) == nil, "schema")
        print("PASS")
    }
}
