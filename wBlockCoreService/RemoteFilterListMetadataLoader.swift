import Foundation

public enum RemoteFilterListMetadataLoader {
    public static func fetch(
        from url: URL,
        session: URLSession = .shared,
        maxBytes: Int = 64 * 1024,
        maxLines: Int = 80
    ) async throws -> (title: String?, description: String?) {
        guard maxBytes > 0, maxLines > 0 else { return (nil, nil) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("bytes=0-\(maxBytes - 1)", forHTTPHeaderField: "Range")

        // Servers can ignore Range. Stop the stream ourselves rather than
        // downloading a whole filter list for an autofill suggestion.
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else { return (nil, nil) }

        var prefix = Data()
        prefix.reserveCapacity(min(maxBytes, 64 * 1024))
        var lines = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            prefix.append(byte)
            if byte == 10 { lines += 1 }
            if prefix.count >= maxBytes || lines >= maxLines { break }
        }
        let content = String(decoding: prefix, as: UTF8.self)
        let metadata = FilterListMetadataParser.parse(from: content, maxLines: maxLines)
        return (metadata.title, metadata.description)
    }
}
