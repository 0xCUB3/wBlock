import Foundation

/// Keep damaged records editable without inventing a remote download endpoint.
public enum PersistedFilterURL {
    public static func resolve(_ raw: String) -> (url: URL, isUsable: Bool) {
        if let url = URL(string: raw),
           (url.isFileURL || isInlineUserList(url)
            || (["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty)) {
            return (url, true)
        }
        if let url = URL(string: raw), url.scheme == "wblock-invalid-filter" {
            // Older versions rejected inline lists and persisted their original URL here.
            if let source = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "source" })?.value,
               let originalURL = URL(string: source), isInlineUserList(originalURL) {
                return (originalURL, true)
            }
            return (url, false)
        }
        var placeholder = URLComponents()
        placeholder.scheme = "wblock-invalid-filter"
        placeholder.path = "unavailable"
        placeholder.queryItems = [URLQueryItem(name: "source", value: raw)]
        return (placeholder.url!, false)
    }

    private static func isInlineUserList(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "wblock" && url.host?.lowercased() == "userlist"
    }
}
