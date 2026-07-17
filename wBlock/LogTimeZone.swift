//
//  LogTimeZone.swift
//  wBlock
//
//  Created by Codex on 2/13/26.
//

import Foundation

/// User-facing preference controlling the time zone used to render log timestamps.
///
/// See GitHub issue #472. By default log timestamps follow the device's current
/// time zone ("Sync with device"). Users may instead pin timestamps to a specific
/// time zone from Settings.
enum LogTimeZonePreference {
    /// Storage key for the chosen `TimeZone` identifier (empty == device timezone).
    static let storageKey = "logTimeZoneIdentifier"

    /// Sentinel meaning "use the device's current time zone".
    static let deviceIdentifier = ""

    /// Whether the user opted to pin log timestamps to a specific time zone.
    static var usesCustomTimeZone: Bool {
        !storedIdentifier.isEmpty
    }

    static var storedIdentifier: String {
        UserDefaults.standard.string(forKey: storageKey) ?? deviceIdentifier
    }

    /// The effective time zone applied to log timestamps.
    static var current: TimeZone {
        let id = storedIdentifier
        if id.isEmpty { return .autoupdatingCurrent }
        return TimeZone(identifier: id) ?? .autoupdatingCurrent
    }
}

extension TimeZone {
    /// Localized, user-friendly name for a time zone identifier, falling back to
    /// the raw identifier when resolution fails (e.g. invalid or deprecated ids).
    static func localizedName(for identifier: String) -> String? {
        guard let timeZone = TimeZone(identifier: identifier) else { return nil }
        return timeZone.localizedName(for: .shortGeneric, locale: .appCurrent)
    }
}

/// Centralized, preference-aware date formatters for log timestamps.
///
/// `DateFormatter` is mutated only on the settings change path (under a lock);
/// reads return the cached formatter. Existing call sites previously created
/// their own static formatters with no explicit time zone, which silently used
/// the device time zone. This keeps that default while honoring an optional
/// user-chosen time zone.
enum LogDateFormatters {
    private static let lock = NSLock()
    private static var cachedIdentifier: String? = nil
    private static var timeFormatterCache: DateFormatter = makeFormatter(dateFormat: "HH:mm:ss")
    private static var exportTimeFormatterCache: DateFormatter = makeFormatter(dateFormat: "yyyy-MM-dd HH:mm:ss")

    private static func makeFormatter(dateFormat: String, timeZone: TimeZone = .autoupdatingCurrent) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        formatter.timeZone = timeZone
        return formatter
    }

    /// Rebuild and swap cached formatters if the stored time zone preference changed.
    /// New immutable formatter instances are swapped in under the lock so concurrent
    /// readers safely keep using the previously cached (unmutated) instance.
    static func configureIfNeeded() {
        let id = LogTimeZonePreference.storedIdentifier
        lock.lock()
        guard id != cachedIdentifier else {
            lock.unlock()
            return
        }
        cachedIdentifier = id
        let timeZone = LogTimeZonePreference.current
        timeFormatterCache = makeFormatter(dateFormat: "HH:mm:ss", timeZone: timeZone)
        exportTimeFormatterCache = makeFormatter(dateFormat: "yyyy-MM-dd HH:mm:ss", timeZone: timeZone)
        lock.unlock()
    }

    /// Formatter used for the compact in-app log row timestamp.
    static var timeFormatter: DateFormatter {
        configureIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return timeFormatterCache
    }

    /// Formatter used when exporting logs to a text file.
    static var exportTimeFormatter: DateFormatter {
        configureIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return exportTimeFormatterCache
    }
}
