import Foundation

/// Fallback endpoints derived from a built-in list's primary URL.
public enum FilterListURLMirror {
    public static func allowsFallback(primary: URL, fallback: URL) -> Bool {
        // A mirror must keep the same platform, list, and optimized/full variant.
        if let source = registryPath(for: primary), let mirror = registryPath(for: fallback), source != mirror {
            return false
        }
        guard fallback.host?.lowercased() == "filters.adtidy.org" else { return true }
        let primaryPath = primary.path.lowercased()
        let fallbackPath = fallback.path.lowercased()
        if primaryPath.contains("filter_17_trackparam") || primaryPath.contains("/17_") {
            return false
        }
        let isSafariPrimary = primaryPath.contains("/platforms/extension/safari/filters/")
            || (primary.host?.lowercased() == "filters.adtidy.org" && primaryPath.hasPrefix("/extension/safari/filters/"))
        return !(isSafariPrimary && fallbackPath.contains("/ios/filters/"))
    }

    private static func registryPath(for url: URL) -> String? {
        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        if host == "filters.adtidy.org" {
            return path.hasPrefix("/extension/safari/filters/") || path.hasPrefix("/ios/filters/") ? path : nil
        }
        guard (host == "raw.githubusercontent.com" && path.hasPrefix("/adguardteam/filtersregistry/"))
            || (host == "cdn.jsdelivr.net" && path.hasPrefix("/gh/adguardteam/filtersregistry@")),
              let range = path.range(of: "/platforms") else { return nil }
        return String(path[range.upperBound...])
    }

    /// R2 public bucket for the Bypass Paywalls Clean list; the worker serves the
    /// same object through its edge cache if the bucket URL ever fails.
    static let bpcBucketURL = URL(string: "https://pub-d303b9085c0b41b5aa749fc74609d4d9.r2.dev/bpc-paywall-filter.txt")!
    static let bpcWorkerURL = URL(string: "https://bpc-filter-proxy.wmailrelayb8d890.workers.dev")!

    public static func fallbackURLs(for primary: URL) -> [URL] {
        guard primary.scheme?.lowercased() == "https",
              let host = primary.host?.lowercased() else { return [] }
        if primary == bpcBucketURL { return [bpcWorkerURL] }
        if host == "filters.adtidy.org" {
            guard let path = registryPath(for: primary),
                  let registry = URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms\(path)") else { return [] }
            return ([registry] + fallbackURLs(for: registry)).filter {
                $0 != primary && allowsFallback(primary: primary, fallback: $0)
            }
        }
        if host == "cdn.jsdelivr.net" { return [] }
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
        // AdGuard publishes each registry platform at the same path on its own CDN.
        let platforms = ["platforms/extension/safari/filters/": "extension/safari/filters/",
                         "platforms/ios/filters/": "ios/filters/"]
        if user == "AdguardTeam" && repo == "FiltersRegistry",
           let (prefix, adtidyPath) = platforms.first(where: { jsPath.hasPrefix($0.key) }) {
            let filename = String(jsPath.dropFirst(prefix.count))
            // filter 17 is not published at AdGuard's Safari endpoint.
            if filename != "filter.txt" && filename != "filter_17_TrackParam.txt"
                && !filename.hasPrefix("17_") {
                result.insert(URL(string: "https://filters.adtidy.org/\(adtidyPath)\(filename)")!, at: 0)
            }
        }
        var seen = Set<URL>()
        return result.filter {
            allowsFallback(primary: primary, fallback: $0) && seen.insert($0).inserted
        }
    }
}
