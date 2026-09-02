//
//  ConcurrentLogManager.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import Foundation
import wBlockCoreService

/// Log severity levels following Swift-Log best practices
public enum LogLevel: String, Codable, Comparable, CaseIterable {
    case trace   // Detailed diagnostics, not for production
    case debug   // High-value operational info
    case info    // Significant events, recoverable failures
    case warning // One-time warnings, deprecations
    case error   // Errors requiring attention

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let order: [LogLevel] = [.trace, .debug, .info, .warning, .error]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }

    var emoji: String {
        switch self {
        case .trace: return "🔍"
        case .debug: return "🐛"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }
}

/// Log category for better organization
public enum LogCategory: String, Codable {
    case system = "System"
    case filterUpdate = "FilterUpdate"
    case filterApply = "FilterApply"
    case userScript = "UserScript"
    case network = "Network"
    case whitelist = "Whitelist"
    case autoUpdate = "AutoUpdate"
    case startup = "Startup"
}

/// Structured log entry with metadata support
public struct LogEntry: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogCategory
    public let message: String
    public let metadata: [String: String]?
    public var count: Int // For deduplication

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        metadata: [String: String]? = nil,
        count: Int = 1
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
        self.count = count
    }

    /// Check if this entry can be deduplicated with another
    func canDeduplicate(with other: LogEntry) -> Bool {
        self.level == other.level &&
        self.category == other.category &&
        self.message == other.message &&
        self.metadata == other.metadata
    }

    /// Compact single-line format
    var compactFormat: String {
        let time = LogDateFormatters.timeFormatter.string(from: timestamp)
        let metaStr = metadata?.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") ?? ""
        let meta = metaStr.isEmpty ? "" : " (\(metaStr))"
        let countStr = count > 1 ? " ×\(count)" : ""
        return "\(time) [\(level.rawValue.uppercased())] \(category.rawValue): \(message)\(meta)\(countStr)"
    }

    /// Export format for txt file
    var exportFormat: String {
        let time = LogDateFormatters.exportTimeFormatter.string(from: timestamp)
        var lines = ["\(time) [\(level.rawValue.uppercased())] \(category.rawValue): \(message)"]
        if let metadata = metadata, !metadata.isEmpty {
            lines.append("  Metadata: \(metadata.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
        }
        if count > 1 {
            lines.append("  Repeated: \(count) times")
        }
        return lines.joined(separator: "\n")
    }

}

/// Concurrency-safe logger with structured logging and deduplication
public actor ConcurrentLogManager {

    private let maxLogEntries: Int = 5_000
    private let cleanupThreshold: Int = 6_000
    private let deduplicationWindow: TimeInterval = 60 // 1 minute

    private var logEntries: [LogEntry] = []
    private let iso8601Formatter = ISO8601DateFormatter()
    private let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static let shared = ConcurrentLogManager()

    private init() {}

    /// Log a message with structured metadata
    public func log(
        _ level: LogLevel,
        _ category: LogCategory,
        _ message: String,
        metadata: [String: String]? = nil,
        timestamp: Date = Date(),
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var resolvedMetadata = metadata ?? [:]
        // Warnings and errors record where they came from so a report can be
        // traced back to code without guessing. Info rows stay quiet.
        if level >= .warning, resolvedMetadata["source"] == nil {
            let fileName = file.split(separator: "/").last.map(String.init) ?? file
            resolvedMetadata["source"] = "\(fileName):\(line)"
        }
        let entry = LogEntry(
            timestamp: timestamp,
            level: level,
            category: category,
            message: message,
            metadata: resolvedMetadata.isEmpty ? nil : resolvedMetadata
        )

        // Try to deduplicate with recent entries
        if let lastEntry = logEntries.last,
           lastEntry.canDeduplicate(with: entry),
           entry.timestamp.timeIntervalSince(lastEntry.timestamp) >= 0,
           entry.timestamp.timeIntervalSince(lastEntry.timestamp) < deduplicationWindow {
            // Increment count on last entry
            logEntries[logEntries.count - 1].count += 1
        } else {
            // Add new entry
            logEntries.append(entry)

            // Cleanup if needed
            if logEntries.count > cleanupThreshold {
                logEntries.removeFirst(logEntries.count - maxLogEntries)
            }
        }

        // Print to console for debugging
        #if DEBUG
        print(entry.compactFormat)
        #endif

        schedulePersist()
    }

    /// Convenience methods for each log level
    public func trace(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil,
                      file: String = #file, function: String = #function, line: Int = #line) {
        log(.trace, category, message, metadata: metadata, file: file, function: function, line: line)
    }

    public func debug(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil,
                      file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, category, message, metadata: metadata, file: file, function: function, line: line)
    }

    public func info(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil,
                     file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, category, message, metadata: metadata, file: file, function: function, line: line)
    }

    public func warning(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil,
                        file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, category, message, metadata: metadata, file: file, function: function, line: line)
    }

    public func error(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil,
                      file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, category, message, metadata: metadata, file: file, function: function, line: line)
    }

    /// Logs an error together with a full description of the thrown value
    /// (domain, code, underlying errors) under the `error` metadata key.
    public func error(_ category: LogCategory, _ message: String, error: Error,
                      metadata: [String: String] = [:],
                      file: String = #file, function: String = #function, line: Int = #line) {
        var merged = metadata
        merged["error"] = LogErrorDescriber.describe(error)
        log(.error, category, message, metadata: merged, file: file, function: function, line: line)
    }

    public func warning(_ category: LogCategory, _ message: String, error: Error,
                        metadata: [String: String] = [:],
                        file: String = #file, function: String = #function, line: Int = #line) {
        var merged = metadata
        merged["error"] = LogErrorDescriber.describe(error)
        log(.warning, category, message, metadata: merged, file: file, function: function, line: line)
    }

    // MARK: - Environment

    /// App and OS details that every bug report needs. Written once per launch
    /// as the first Startup entry and repeated in the export header.
    public nonisolated static var environmentDetails: [String: String] {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let platform = "macOS"
        #else
        let platform = "iOS"
        #endif
        var details: [String: String] = [
            "app": "\(version) (\(build))",
            "os": "\(platform) \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "device": deviceModelIdentifier,
            "locale": Locale.current.identifier,
        ]
        #if DEBUG
        details["configuration"] = "debug"
        #endif
        return details
    }

    private nonisolated static var deviceModelIdentifier: String {
        #if os(macOS)
        // On macOS utsname.machine is the CPU architecture; hw.model holds the Mac model.
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 {
                let model = String(cString: buffer)
                if !model.isEmpty { return model }
            }
        }
        #endif
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return machine.isEmpty ? "unknown" : machine
    }

    /// Records the app launch with version and OS details. Call once at startup.
    public func logLaunch() {
        loadPersistedEntriesIfNeeded()
        log(.info, .startup, LocalizedStrings.text("wBlock launched"), metadata: Self.environmentDetails)
    }

    // MARK: - Persistence

    private var hasLoadedPersistedEntries = false
    private var persistTask: Task<Void, Never>?
    private let persistDebounceSeconds: UInt64 = 2

    private nonisolated static var persistedLogURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("wBlock", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("logs.json")
    }

    /// Loads entries saved by a previous launch. Safe to call repeatedly.
    public func loadPersistedEntriesIfNeeded() {
        guard !hasLoadedPersistedEntries else { return }
        hasLoadedPersistedEntries = true
        guard let url = Self.persistedLogURL,
              let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([LogEntry].self, from: data),
              !saved.isEmpty else { return }
        let existingIDs = Set(logEntries.map(\.id))
        let merged = saved.filter { !existingIDs.contains($0.id) } + logEntries
        logEntries = Array(merged.sorted { $0.timestamp < $1.timestamp }.suffix(maxLogEntries))
    }

    private func schedulePersist() {
        guard persistTask == nil else { return }
        let delay = persistDebounceSeconds
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.persistNow()
        }
    }

    /// Writes the in-memory entries to disk. Runs on a debounce after each
    /// log and on demand before the app goes away.
    public func persistNow() {
        persistTask?.cancel()
        persistTask = nil
        guard let url = Self.persistedLogURL else { return }
        let snapshot = Array(logEntries.suffix(maxLogEntries))
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("Failed to persist logs: \(error)")
            #endif
        }
    }

    private func removePersistedEntries() {
        guard let url = Self.persistedLogURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Get all log entries (for the UI)
    public func getEntries() -> [LogEntry] {
        loadPersistedEntriesIfNeeded()
        return logEntries.sorted { $0.timestamp < $1.timestamp }
    }

    /// Get entries filtered by level
    public func getEntries(minLevel: LogLevel) -> [LogEntry] {
        return logEntries.filter { $0.level >= minLevel }.sorted { $0.timestamp < $1.timestamp }
    }

    /// Get entries filtered by category
    public func getEntries(category: LogCategory) -> [LogEntry] {
        return logEntries.filter { $0.category == category }.sorted { $0.timestamp < $1.timestamp }
    }

    /// Export logs as formatted text
    public func exportAsText(entries requestedEntries: [LogEntry]? = nil) -> String {
        let entries = (requestedEntries ?? logEntries).sorted { $0.timestamp < $1.timestamp }
        let generated = LogDateFormatters.exportTimeFormatter.string(from: Date())
        let timeZoneLabel = LogTimeZonePreference.usesCustomTimeZone
            ? LogTimeZonePreference.storedIdentifier
            : NSLocalizedString("Device timezone", comment: "Log export time zone label")
        let environment = Self.environmentDetails
        let header = """
        wBlock Logs Export
        Generated: \(generated)
        Time Zone: \(timeZoneLabel)
        App: \(environment["app"] ?? "?")
        OS: \(environment["os"] ?? "?")
        Device: \(environment["device"] ?? "?")
        Total Entries: \(entries.count)
        ════════════════════════════════════════

        """

        return header + entries.map { $0.exportFormat }.joined(separator: "\n\n")
    }

    /// Clear all log entries
    public func clearLogs() {
        logEntries.removeAll()
        persistTask?.cancel()
        persistTask = nil
        removePersistedEntries()
        _ = drainSharedLog(at: sharedAutoUpdateLogURL())
        _ = drainSharedLog(at: sharedWebExtensionLogURL())
    }

    // MARK: - Shared Auto-Update Log Ingestion

    private func sharedAutoUpdateLogURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value)?
            .appendingPathComponent("auto_update.log")
    }

    private func sharedWebExtensionLogURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value)?
            .appendingPathComponent("web_extension.log")
    }

    public func ingestSharedAutoUpdateLog() {
        guard let content = drainSharedLog(at: sharedAutoUpdateLogURL()) else { return }

        let lines = content.split(separator: "\n").map(String.init)
        let parsedResults = lines.compactMap { parseSharedFieldsLine($0, prefix: "telemetry ") }
            .filter { $0.fields["event"] == "run result" }
        let results = parsedResults.filter {
            let fields = $0.fields
            let helperTriggers = ["XPCService", "LaunchAgent", "LegacyLoginItem"]
            return !(fields["result"] == "failed"
                && fields["phase"] == "content blocker reload"
                && helperTriggers.contains(fields["trigger"] ?? ""))
        }

        if parsedResults.isEmpty {
            for line in lines {
                if parseSharedFieldsLine(line, prefix: "telemetry ") != nil { continue }
                let parsed = parseSharedLine(line)
                if shouldIgnoreLegacyHelperReloadFailure(parsed.body) { continue }
                let level: LogLevel = parsed.body.localizedCaseInsensitiveContains("failed") ? .error
                    : parsed.body.localizedCaseInsensitiveContains("deferred") ? .warning : .debug
                log(level, .autoUpdate, parsed.body, timestamp: parsed.timestamp ?? Date())
            }
            return
        }

        for result in results {
            var metadata = result.fields
            metadata.removeValue(forKey: "event")
            let outcome = metadata.removeValue(forKey: "result") ?? "unknown"
            let level: LogLevel = outcome == "failed" ? .error : outcome == "deferred" ? .warning : .info
            log(
                level,
                .autoUpdate,
                LocalizedStrings.format("Auto-update: %@", outcome),
                metadata: metadata,
                timestamp: result.timestamp ?? Date()
            )
        }

        for line in lines where parseSharedFieldsLine(line, prefix: "telemetry ") == nil {
            let parsed = parseSharedLine(line)
            if shouldIgnoreLegacyHelperReloadFailure(parsed.body) { continue }
            let level: LogLevel?
            if parsed.body.localizedCaseInsensitiveContains("failed") {
                level = .error
            } else if parsed.body.localizedCaseInsensitiveContains("deferred") {
                level = .warning
            } else {
                level = nil
            }
            guard let level else { continue }
            let represented = parsedResults.contains { result in
                guard let rawTimestamp = parsed.timestamp,
                      let resultTimestamp = result.timestamp else { return false }
                return abs(rawTimestamp.timeIntervalSince(resultTimestamp)) < 5
                    && (result.fields["result"] == "failed" || result.fields["result"] == "deferred")
            }
            if !represented {
                log(level, .autoUpdate, parsed.body, timestamp: parsed.timestamp ?? Date())
            }
        }
    }

    private func shouldIgnoreLegacyHelperReloadFailure(_ body: String) -> Bool {
        let normalized = body.replacingOccurrences(of: "_", with: " ")
        let helperTriggers = ["XPCService", "LaunchAgent", "LegacyLoginItem"]
        return normalized.contains("Auto-update failed:")
            && normalized.contains("phase=content blocker reload")
            && helperTriggers.contains { normalized.contains("trigger=\($0)") }
    }

    private func shouldIgnoreSharedWebExtensionDiagnostic(_ fields: [String: String]) -> Bool {
        func normalizedValue(for key: String) -> String {
            fields[key]?.replacingOccurrences(of: " ", with: "_") ?? ""
        }

        guard normalizedValue(for: "event") == "support_decision",
              normalizedValue(for: "source") == "background",
              normalizedValue(for: "outcome") == "unsupported" else { return false }
        let reason = normalizedValue(for: "reason")
        return reason == "missing_url"
            || (reason == "unsupported_scheme" && normalizedValue(for: "protocol") == "favorites:")
    }

    public func ingestSharedWebExtensionLog() {
        guard let content = drainSharedLog(at: sharedWebExtensionLogURL()) else { return }

        for line in content.split(separator: "\n").map(String.init) {
            if let parsed = parseSharedFieldsLine(line, prefix: "diagnostic ") {
                guard !shouldIgnoreSharedWebExtensionDiagnostic(parsed.fields) else { continue }
                var metadata = parsed.fields
                metadata.removeValue(forKey: "event")
                let event = parsed.fields["event"] ?? "diagnostic"
                log(
                    .debug,
                    .system,
                    LocalizedStrings.format("Web extension %@", event),
                    metadata: metadata,
                    timestamp: parsed.timestamp ?? Date()
                )
            } else {
                let parsed = parseSharedLine(line)
                log(.debug, .system, parsed.body, metadata: ["source": "web-extension"], timestamp: parsed.timestamp ?? Date())
            }
        }
    }

    private func drainSharedLog(at sourceURL: URL?) -> String? {
        guard let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }
        let drainedURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("\(sourceURL.lastPathComponent).\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: sourceURL, to: drainedURL)
            let content = try String(contentsOf: drainedURL, encoding: .utf8)
            try FileManager.default.removeItem(at: drainedURL)
            return content.isEmpty ? nil : content
        } catch {
            if FileManager.default.fileExists(atPath: drainedURL.path),
               !FileManager.default.fileExists(atPath: sourceURL.path) {
                try? FileManager.default.moveItem(at: drainedURL, to: sourceURL)
            }
            return nil
        }
    }

    private func parseSharedLine(_ line: String) -> (timestamp: Date?, body: String) {
        guard line.first == "[", let bracketEnd = line.firstIndex(of: "]") else { return (nil, line) }
        let timestampText = String(line[line.index(after: line.startIndex)..<bracketEnd])
        let bodyStart = line.index(after: bracketEnd)
        let timestamp = iso8601Formatter.date(from: timestampText)
            ?? iso8601FractionalFormatter.date(from: timestampText)
        return (
            timestamp,
            String(line[bodyStart...]).trimmingCharacters(in: .whitespaces)
        )
    }

    private func parseSharedFieldsLine(
        _ line: String,
        prefix: String
    ) -> (timestamp: Date?, fields: [String: String])? {
        let parsed = parseSharedLine(line)
        guard parsed.body.hasPrefix(prefix) else { return nil }
        let payload = parsed.body.dropFirst(prefix.count)
        var metadata: [String: String] = [:]

        for token in payload.split(separator: " ") {
            guard let separator = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<separator])
            let value = String(token[token.index(after: separator)...])
            metadata[key] = value.replacingOccurrences(of: "_", with: " ")
        }

        return metadata.isEmpty ? nil : (parsed.timestamp, metadata)
    }
}
