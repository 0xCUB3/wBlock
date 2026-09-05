import Foundation

/// Reuses the existing preference storage so separating DeArrow preserves its options.
public enum DeArrowPreference {
    public typealias Settings = TubeCleanerDeArrowPreference.Settings
    public static let scriptURL = "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/dearrow/dist/dearrow.user.js"
    public static let settingsConstantName = "__wblockDeArrowSettings"

    public static func matches(scriptURL: URL?) -> Bool {
        scriptURL?.absoluteString == self.scriptURL
    }

    public static func normalizedChannel(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let identifier = channelIdentifier(candidate) { return identifier }
        let absolute = candidate.hasPrefix("/") ? "https://www.youtube.com" + candidate
            : (candidate.contains("://") ? candidate : "https://" + candidate)
        guard let components = URLComponents(string: absolute),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(),
              ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"].contains(host)
        else { return nil }
        let encodedParts = components.percentEncodedPath.split(separator: "/")
        let parts = encodedParts.compactMap { String($0).removingPercentEncoding }
        guard parts.count == encodedParts.count else { return nil }
        guard let identifier = parts.first == "channel" ? parts.dropFirst().first : parts.first else { return nil }
        return channelIdentifier(identifier)
    }

    public static func normalizedChannels(_ values: [String]) -> [String] {
        Array(Set(values.compactMap(normalizedChannel))).sorted()
    }

    private static func channelIdentifier(_ value: String) -> String? {
        let normalized = value.precomposedStringWithCanonicalMapping
        if normalized.range(of: #"^UC[A-Za-z0-9_-]{22}\z"#, options: .regularExpression) != nil { return normalized }
        if normalized.range(of: #"^@[\p{L}\p{N}\p{M}._\-·]{1,100}\z"#, options: .regularExpression) != nil {
            return normalized.lowercased()
        }
        return nil
    }

    public static func configuredExecutableContent(_ content: String, settings: Settings) -> String {
        // Script enablement owns the on/off state; the legacy bit is only for migration.
        var configured = settings
        configured.enabled = true
        if let channels = configured.originalThumbnailChannels {
            configured.originalThumbnailChannels = normalizedChannels(channels)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = (try? encoder.encode(configured)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "const \(settingsConstantName) = \(json);\n\(content)"
    }
}
