import Foundation

@main
struct FilterListFlagTests {
    static func main() {
        let filter = FilterList(
            name: "Regional",
            url: URL(string: "https://example.com/filter.txt")!,
            category: .foreign,
            languages: ["hi", "ta", "te", "ne", "si", "hi"]
        )
        guard filter.flagEmojis == "🇮🇳 🇳🇵 🇱🇰" else {
            fatalError("repeated country flags must be collapsed while preserving order")
        }
        print("PASS")
    }
}
