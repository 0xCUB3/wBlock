import Foundation

public enum RetiredUserScriptSources {
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
