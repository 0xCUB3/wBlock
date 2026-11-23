//
//  HTTPModifiedDate.swift
//  wBlockCoreService
//

import Foundation

/// Parses HTTP date headers so rows can show when the upstream content
/// actually changed instead of when wBlock happened to download it.
public enum HTTPModifiedDate {
    private static let parsers: [DateFormatter] = {
        // RFC 1123 plus the two legacy variants a server may still send.
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy",
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "GMT")
            return formatter
        }
    }()

    public static func date(from headerValue: String?) -> Date? {
        guard let headerValue, !headerValue.isEmpty else { return nil }
        for parser in parsers {
            if let date = parser.date(from: headerValue) { return date }
        }
        return nil
    }
}

/// Last-Modified headers of downloaded userscript content, keyed by source
/// URL. The protobuf schema carries no script validator fields, so this
/// display hint lives in the app group defaults; losing it only falls back to
/// the local download time.
public enum UserScriptModifiedStore {
    private static let key = "wblock.userScriptLastModified"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
    }

    public static func date(for url: URL?) -> Date? {
        guard let urlString = url?.absoluteString else { return nil }
        guard let map = defaults.dictionary(forKey: key) as? [String: String] else { return nil }
        return HTTPModifiedDate.date(from: map[urlString])
    }

    /// Resolves the newest recorded Last-Modified date across a script's
    /// `@downloadURL` and catalog/source URL so updates fetched from a
    /// script-declared `@downloadURL` never display a stale initial-install date.
    public static func date(for script: UserScript) -> Date? {
        let candidates = [script.resolvedDownloadURL, script.url].compactMap { date(for: $0) }
        return candidates.max()
    }

    public static func record(_ headerValue: String?, for url: URL?) {
        guard let url else { return }
        record(headerValue, for: [url])
    }

    public static func record(_ headerValue: String?, for urls: [URL]) {
        guard !urls.isEmpty else { return }
        let urlStrings = Set(urls.map(\.absoluteString))
        var map = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        var changed = false
        if let headerValue, !headerValue.isEmpty {
            for urlString in urlStrings where map[urlString] != headerValue {
                map[urlString] = headerValue
                changed = true
            }
        } else {
            for urlString in urlStrings where map.removeValue(forKey: urlString) != nil {
                changed = true
            }
        }
        if changed {
            defaults.set(map, forKey: key)
        }
    }
}
