import Foundation

@main
struct RetiredUserScriptSourceTests {
    static func main() {
        let retired = [
            "https://cdn.jsdelivr.net/gh/adamlui/youtube-classic/greasemonkey/youtube-classic.user.js",
            "https://cdn.jsdelivr.net/gh/adamlui/youtube-classic@main/greasemonkey/youtube-classic.user.js",
            "https://raw.githubusercontent.com/adamlui/youtube-classic/main/greasemonkey/youtube-classic.user.js",
            "https://github.com/adamlui/youtube-classic/raw/main/greasemonkey/youtube-classic.user.js",
        ]
        let maintained = [
            "https://codeberg.org/adamlui/youtube-classic/raw/branch/main/greasemonkey/youtube-classic.user.js",
            "https://scriptcat.org/scripts/code/6345/youtube-classic.user.js",
            "https://example.com/adamlui/youtube-classic/custom.user.js",
            "https://cdn.jsdelivr.net/gh/adamlui/youtube-classic-fork/custom.user.js",
            "https://github.com/adamlui/youtube-classic-fork/custom.user.js",
        ]
        for value in retired + maintained {
            precondition(
                RetiredUserScriptSources.isYouTubeClassic(URL(string: value)!) == retired.contains(value),
                "Retirement must match the old source, not just the repository name: \(value)"
            )
        }
        print("PASS: retired source identity (\(retired.count + maintained.count) URLs)")
    }
}
