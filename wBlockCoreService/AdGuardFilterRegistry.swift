import Foundation

/// A list from AdGuard's Safari filter registry, ready to add as a custom list.
public struct AdGuardRegistryList: Identifiable, Hashable, Sendable {
    public let id: Int
    /// Its Safari-optimized download, with the registry's name, description,
    /// category, and languages.
    public let filter: FilterList
    /// Every address the list is published at: the download, its upstream
    /// source, and the registry's mirrors of the download.
    public let knownURLs: [URL]

    public func isSameList(as url: URL) -> Bool {
        knownURLs.contains { FilterListURLSupport.isSameList($0, url) }
    }
}

/// AdGuard's filter registry for Safari, so people can find lists wBlock
/// doesn't include. Fetched only when asked for, refreshed at most daily, and
/// served from the last good copy when offline.
public enum AdGuardFilterRegistry {
    public static let sourceURL = URL(string:
        "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/platforms/extension/safari/filters.json")!
    static let refreshInterval: TimeInterval = 24 * 60 * 60

    private struct Payload: Decodable {
        struct Entry: Decodable {
            let filterId: Int
            let name: String
            let description: String?
            let groupId: Int
            let languages: [String]?
            let deprecated: Bool?
            let subscriptionUrl: URL?
            let downloadUrl: URL
        }
        let filters: [Entry]
    }

    /// Registry lists still maintained, in the registry's order.
    public static func lists(from data: Data) throws -> [AdGuardRegistryList] {
        try JSONDecoder().decode(Payload.self, from: data).filters.compactMap { entry in
            guard entry.deprecated != true, entry.downloadUrl.scheme?.lowercased() == "https" else { return nil }
            let category = category(filterID: entry.filterId, groupID: entry.groupId)
            let filter = FilterList(
                name: entry.name, url: entry.downloadUrl, category: category, isCustom: true,
                description: entry.description ?? "",
                languages: category == .foreign ? entry.languages ?? [] : [])
            var urls = [entry.downloadUrl] + FilterListURLMirror.fallbackURLs(for: entry.downloadUrl)
            if let source = entry.subscriptionUrl { urls.append(source) }
            return AdGuardRegistryList(id: entry.filterId, filter: filter, knownURLs: urls)
        }
    }

    /// The registry's groups mapped onto wBlock's categories. Its "Other" group
    /// mixes an allowlist and an experimental list with privacy lists.
    static func category(filterID: Int, groupID: Int) -> FilterListCategory {
        switch (filterID, groupID) {
        case (5, _): return .experimental
        case (10, _): return .allowlists
        case (_, 1): return .ads
        case (_, 2): return .privacy
        case (_, 3), (_, 4): return .annoyances
        case (_, 5): return .security
        case (_, 7): return .foreign
        default: return .custom
        }
    }

    public static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("adguard-safari-filter-registry.json")
    }

    public static func load(
        session: URLSession = .shared,
        cacheURL: URL? = defaultCacheURL,
        now: Date = Date()
    ) async throws -> [AdGuardRegistryList] {
        let cached = cacheURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? lists(from: $0) }
        let cacheDate = cacheURL.flatMap {
            try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date
        }
        if let cached, let cacheDate, now.timeIntervalSince(cacheDate) < refreshInterval {
            return cached
        }
        var lastError: Error = URLError(.badServerResponse)
        for url in [sourceURL] + FilterListURLMirror.fallbackURLs(for: sourceURL) {
            do {
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let fresh = try lists(from: data)
                guard !fresh.isEmpty else { throw URLError(.cannotDecodeContentData) }
                if let cacheURL { try? data.write(to: cacheURL, options: .atomic) }
                return fresh
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                lastError = error
            }
        }
        if let cached { return cached }
        throw lastError
    }
}
