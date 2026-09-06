import Foundation

/// Fallback endpoints derived from a built-in list's primary URL.
public enum FilterListURLMirror {
    public static func allowsFallback(primary: URL, fallback: URL) -> Bool {
        guard fallback.host?.lowercased() == "filters.adtidy.org" else { return true }
        let primaryPath = primary.path.lowercased()
        let fallbackPath = fallback.path.lowercased()
        if primaryPath.contains("filter_17_trackparam") || primaryPath.contains("/17_") {
            return false
        }
        let isSafariPrimary = primaryPath.contains("/platforms/extension/safari/filters/")
            || primary.host?.lowercased() == "filters.adtidy.org"
        return !(isSafariPrimary && fallbackPath.contains("/ios/filters/"))
    }

    /// R2 public bucket for the Bypass Paywalls Clean list; the worker serves the
    /// same object through its edge cache if the bucket URL ever fails.
    static let bpcBucketURL = URL(string: "https://pub-d303b9085c0b41b5aa749fc74609d4d9.r2.dev/bpc-paywall-filter.txt")!
    static let bpcWorkerURL = URL(string: "https://bpc-filter-proxy.wmailrelayb8d890.workers.dev")!

    public static func fallbackURLs(for primary: URL) -> [URL] {
        guard primary.scheme?.lowercased() == "https",
              let host = primary.host?.lowercased() else { return [] }
        if primary == bpcBucketURL { return [bpcWorkerURL] }
        if host == "cdn.jsdelivr.net" || host == "filters.adtidy.org" { return [] }
        guard host == "raw.githubusercontent.com" else { return [] }
        // Use the encoded path: URL.path decodes spaces and other characters, which
        // would make the derived URL invalid when it is rebuilt from a string.
        guard let encodedPath = URLComponents(url: primary, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return [] }
        let parts = encodedPath.split(separator: "/").map(String.init)
        guard parts.count >= 4 else { return [] }
        let user = parts[0], repo = parts[1], ref = parts[2]
        let path = parts.dropFirst(3).joined(separator: "/")
        // List-KR has an intentional URL migration in the app catalog.
        if user.caseInsensitiveCompare("List-KR") == .orderedSame { return [] }
        let jsRef = ref == "refs" && parts.count >= 5 && parts[3] == "heads"
            ? (parts[4]) : ref
        let jsPath = (ref == "refs" && parts.count >= 5 && parts[3] == "heads")
            ? parts.dropFirst(5).joined(separator: "/") : path
        var jsDelivrComponents = URLComponents()
        jsDelivrComponents.scheme = "https"
        jsDelivrComponents.host = "cdn.jsdelivr.net"
        jsDelivrComponents.percentEncodedPath = "/gh/\(user)/\(repo)@\(jsRef)/\(jsPath)"
        guard let jsDelivr = jsDelivrComponents.url else { return [] }
        var result = [jsDelivr]
        let isSafariRegistry = user == "AdguardTeam" && repo == "FiltersRegistry"
            && jsPath.hasPrefix("platforms/extension/safari/filters/")
        if isSafariRegistry {
            let filename = String(jsPath.dropFirst("platforms/extension/safari/filters/".count))
            // filter 17 is not published at AdGuard's Safari endpoint.
            if filename != "filter.txt" && filename != "filter_17_TrackParam.txt"
                && !filename.hasPrefix("17_") {
                result.insert(URL(string: "https://filters.adtidy.org/extension/safari/filters/\(filename)")!, at: 0)
            }
        }
        var seen = Set<URL>()
        return result.filter {
            allowsFallback(primary: primary, fallback: $0) && seen.insert($0).inserted
        }
    }
}
