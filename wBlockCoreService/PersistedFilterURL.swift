import Foundation

/// Keep damaged records editable without inventing a remote download endpoint.
public enum PersistedFilterURL {
    public static func resolve(_ raw: String) -> (url: URL, isUsable: Bool) {
        if let url = URL(string: raw),
           (url.isFileURL || (["http", "https"].contains(url.scheme?.lowercased() ?? "") && !(url.host ?? "").isEmpty)) {
            return (url, true)
        }
        if let url = URL(string: raw), url.scheme == "wblock-invalid-filter" {
            return (url, false)
        }
        var placeholder = URLComponents()
        placeholder.scheme = "wblock-invalid-filter"
        placeholder.path = "unavailable"
        placeholder.queryItems = [URLQueryItem(name: "source", value: raw)]
        return (placeholder.url!, false)
    }
}
