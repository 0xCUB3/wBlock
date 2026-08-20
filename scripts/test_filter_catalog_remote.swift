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
        check(overlay?.fallbacks(for: FilterList(name: "List", url: target, category: .ads)).count == 1, "overlay fallback")
        let input = [FilterList(name: "List", url: old, category: .ads)]
        check(overlay?.applyReplacements(to: input, defaultURLs: [target]).first?.url == target, "replacement applied")

        let selectedOld = FilterList(id: UUID(), name: "Old", url: old, category: .ads, isSelected: true)
        let defaultList = FilterList(name: "New", url: target, category: .ads)
        let replaced = overlay!.applyReplacements(to: [selectedOld], defaultURLs: [target])
        let merged = FilterCatalogMerge.mergeDefaults(into: replaced, defaults: [defaultList])
        check(merged.count == 1 && merged[0].id == selectedOld.id && merged[0].isSelected, "replacement duplicate collapsed with selection")

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

        let http = Data("{\"schemaVersion\":1,\"lists\":[{\"name\":\"bad\",\"url\":\"http://example.com/list.txt\"}]}".utf8)
        check(FilterCatalogOverlay.parse(http, defaultURLs: []) == nil, "http rejected")
        check(FilterCatalogOverlay.parse(Data("{\"schemaVersion\":2,\"lists\":[]}".utf8), defaultURLs: []) == nil, "schema")
        print("PASS")
    }
}
