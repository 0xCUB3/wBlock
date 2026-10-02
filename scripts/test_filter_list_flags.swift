import Foundation

@main
struct FilterListFlagTests {
    static func main() {
        let indian = FilterList(
            name: "Regional",
            url: URL(string: "https://example.com/filter.txt")!,
            category: .foreign,
            languages: ["hi", "si", "ne", "bn", "ta", "hi"]
        )
        guard indian.flagEmojis == "\u{1F1EE}\u{1F1F3} \u{1F1F1}\u{1F1F0} \u{1F1F3}\u{1F1F5} \u{1F1E7}\u{1F1E9}" else {
            fatalError("repeated country flags must be collapsed while preserving order")
        }
        let chinese = FilterList(name: "Chinese", url: URL(string: "https://example.com/zh.txt")!,
                                 category: .foreign, languages: ["zh"])
        guard chinese.flagEmojis == "\u{1F1E8}\u{1F1F3} \u{1F1F9}\u{1F1FC} \u{1F1ED}\u{1F1F0} \u{1F1F2}\u{1F1F4}",
              FilterList.flag(forLanguage: "zh") == "\u{1F1E8}\u{1F1F3}",
              FilterList.flag(forLanguage: "unknown") == nil else {
            fatalError("a language can carry several region flags")
        }
        print("PASS")
    }
}
