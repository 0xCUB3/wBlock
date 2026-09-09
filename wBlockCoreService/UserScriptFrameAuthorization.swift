import Foundation

public enum UserScriptFrameAuthorization {
    public static func allows(
        _ script: UserScript,
        pageURL: String,
        isTopFrame: Bool,
        disabledOnSite: Bool,
        paused: Bool
    ) -> Bool {
        guard !paused, !disabledOnSite, script.isEnabled,
              let url = URL(string: pageURL),
              let host = url.host, !host.isEmpty,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              !script.noframes || isTopFrame else { return false }
        return script.matches(url: pageURL)
    }
}
