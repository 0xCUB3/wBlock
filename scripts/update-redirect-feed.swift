// Regenerates wBlockCoreService/Resources/redirect-feed.json: the redirect
// directives AdGuard strips from its Safari builds, taken from the matching
// Chromium builds of every AdGuard list wBlock ships.
//
// Usage (after building wBlockCoreService):
//   P=$(ls -d ~/Library/Developer/Xcode/DerivedData/wBlock-*/Build/Products/Debug | head -1)
//   swiftc -parse-as-library -F "$P" -framework wBlockCoreService -Xlinker -rpath -Xlinker "$P" \
//     scripts/update-redirect-feed.swift -o /tmp/update-redirect-feed && /tmp/update-redirect-feed
import Foundation
import wBlockCoreService

@main
struct UpdateRedirectFeed {
    static func main() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let loader = try String(contentsOf: root.appendingPathComponent("wBlock/FilterListLoader.swift"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"/(?:extension/safari|ios)/filters/(\d+)(?:_optimized)?\.txt"#)
        let ids = Set(regex.matches(in: loader, range: NSRange(loader.startIndex..., in: loader)).compactMap {
            Range($0.range(at: 1), in: loader).map { String(loader[$0]) }
        }).sorted { Int($0)! < Int($1)! }

        var feed: [String: String] = [:]
        for id in ids {
            let url = URL(string: "https://filters.adtidy.org/extension/chromium/filters/\(id)_optimized.txt")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else {
                print("skip \(id): no Chromium build")
                continue
            }
            let lines = RemoveParamDNRRuleGenerator.extractRedirectLines(from: text)
            print("\(id): \(lines.split(separator: "\n").count) lines")
            if !lines.isEmpty { feed[id] = lines }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let output = root.appendingPathComponent("wBlockCoreService/Resources/redirect-feed.json")
        try encoder.encode(feed).write(to: output, options: .atomic)
        print("wrote \(output.path)")
    }
}
