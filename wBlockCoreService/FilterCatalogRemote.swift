import Foundation

public struct FilterCatalogEntry: Codable, Equatable, Sendable {
    public let name: String
    public let url: URL
    public let fallbacks: [URL]
    public let replaceFrom: [URL]

    private enum CodingKeys: String, CodingKey { case name, url, fallbacks, replaceFrom }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(URL.self, forKey: .url)
        fallbacks = try c.decodeIfPresent([URL].self, forKey: .fallbacks) ?? []
        replaceFrom = try c.decodeIfPresent([URL].self, forKey: .replaceFrom) ?? []
    }
}

public struct FilterCatalogOverlay: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let lists: [FilterCatalogEntry]

    public static func parse(_ data: Data, defaultURLs: Set<URL>) -> FilterCatalogOverlay? {
        guard let decoded = try? JSONDecoder().decode(FilterCatalogOverlay.self, from: data), decoded.schemaVersion == 1 else { return nil }
        for entry in decoded.lists {
            guard entry.url.scheme?.lowercased() == "https",
                  entry.fallbacks.allSatisfy({ $0.scheme?.lowercased() == "https" }),
                  entry.replaceFrom.allSatisfy({ $0.scheme?.lowercased() == "https" })
            else { return nil }
        }
        let validLists = decoded.lists.compactMap { entry -> FilterCatalogEntry? in
            // Old replacement URLs intentionally are not in the baked-in
            // catalog. Only accept a replacement when its target is built in.
            guard entry.replaceFrom.isEmpty || defaultURLs.contains(entry.url) else { return nil }
            return entry
        }
        return FilterCatalogOverlay(schemaVersion: decoded.schemaVersion, lists: validLists)
    }

    public func fallbacks(for filter: FilterList) -> [URL] {
        let match = lists.first { $0.url == filter.url || $0.name == filter.name }
        var result = FilterListURLMirror.fallbackURLs(for: filter.url)
        if let match { result.append(contentsOf: match.fallbacks) }
        var seen = Set<URL>()
        return result.filter {
            $0 != filter.url
                && FilterListURLMirror.allowsFallback(primary: filter.url, fallback: $0)
                && seen.insert($0).inserted
        }
    }

    /// Applies only URL replacements whose target is already in the baked-in catalog.
    public func applyReplacements(to filters: [FilterList], defaultURLs: Set<URL>) -> [FilterList] {
        var replacements: [URL: URL] = [:]
        for entry in lists where defaultURLs.contains(entry.url) {
            for old in entry.replaceFrom { replacements[old] = entry.url }
        }
        return filters.map { filter in
            guard let target = replacements[filter.url] else { return filter }
            var copy = filter; copy.url = target; copy.etag = nil; copy.serverLastModified = nil
            return copy
        }
    }
}

public enum FilterCatalogRemote {
    private static var cachedOverlay: FilterCatalogOverlay?
    private static let lock = NSLock()
    private static let cacheKey = "wBlock.filter-catalog.overlay"

    public static func cached() -> FilterCatalogOverlay? { lock.lock(); defer { lock.unlock() }; return cachedOverlay }
    public static func loadCached(defaultURLs: Set<URL>) {
        guard let data = UserDefaults.standard.data(forKey: cacheKey), let overlay = FilterCatalogOverlay.parse(data, defaultURLs: defaultURLs) else { return }
        install(overlay)
    }
    public static func install(_ overlay: FilterCatalogOverlay?) { lock.lock(); cachedOverlay = overlay; lock.unlock() }

    public static func fetch(using session: URLSession, defaultURLs: Set<URL>) async {
        let sources = [
            URL(string: "https://cdn.jsdelivr.net/gh/0xCUB3/wBlock@main/catalog/filter-catalog.json")!,
            URL(string: "https://raw.githubusercontent.com/0xCUB3/wBlock/main/catalog/filter-catalog.json")!
        ]
        for source in sources {
            guard let (data, response) = try? await session.data(from: source),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let overlay = FilterCatalogOverlay.parse(data, defaultURLs: defaultURLs) else { continue }
            UserDefaults.standard.set(data, forKey: cacheKey)
            install(overlay); return
        }
    }
}
