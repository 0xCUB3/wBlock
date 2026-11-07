import Foundation

/// Former built-ins removed from installs and never restored or synced back.
public enum RetiredUserScriptSources {
    private static let youTubeAdBlockURL =
        "https://raw.githubusercontent.com/SysAdminDoc/YoutubeAdblock/main/YoutubeAdblock.user.js"
    /// Safari's own dark mode for websites made it redundant (#1087).
    public static let darkReaderURL =
        "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/dark-reader/dist/dark-reader.user.js"

    public static func isRetired(_ url: URL) -> Bool {
        [youTubeAdBlockURL, darkReaderURL].contains(url.absoluteString) || isYouTubeClassic(url)
    }

    /// Retiring a GitHub source must not remove a custom copy from another host.
    public static func isYouTubeClassic(_ url: URL) -> Bool {
        let prefix: String
        switch url.host?.lowercased() {
        case "github.com", "raw.githubusercontent.com":
            prefix = "/adamlui/youtube-classic"
        case "cdn.jsdelivr.net":
            prefix = "/gh/adamlui/youtube-classic"
        default:
            return false
        }
        let path = url.path
        return path == prefix || path.hasPrefix(prefix + "/") || path.hasPrefix(prefix + "@")
    }
}
