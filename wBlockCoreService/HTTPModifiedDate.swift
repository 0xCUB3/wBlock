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

    public static func record(_ headerValue: String?, for url: URL?) {
        guard let headerValue, !headerValue.isEmpty, let urlString = url?.absoluteString else { return }
        var map = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        guard map[urlString] != headerValue else { return }
        map[urlString] = headerValue
        defaults.set(map, forKey: key)
    }
}
