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
        let time = Self.timeFormatter.string(from: timestamp)
        let metaStr = metadata?.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") ?? ""
        let meta = metaStr.isEmpty ? "" : " (\(metaStr))"
        let countStr = count > 1 ? " ×\(count)" : ""
        return "\(time) [\(level.rawValue.uppercased())] \(category.rawValue): \(message)\(meta)\(countStr)"
    }

    /// Export format for txt file
    var exportFormat: String {
        let time = Self.exportTimeFormatter.string(from: timestamp)
        var lines = ["\(time) [\(level.rawValue.uppercased())] \(category.rawValue): \(message)"]
        if let metadata = metadata, !metadata.isEmpty {
            lines.append("  Metadata: \(metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
        }
        if count > 1 {
            lines.append("  Repeated: \(count) times")
        }
        return lines.joined(separator: "\n")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let exportTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

/// Concurrency-safe logger with structured logging and deduplication
public actor ConcurrentLogManager {

    private let maxLogEntries: Int = 5_000
    private let cleanupThreshold: Int = 6_000
    private let deduplicationWindow: TimeInterval = 60 // 1 minute

    private var logEntries: [LogEntry] = []

    public static let shared = ConcurrentLogManager()

    private init() {}

    /// Log a message with structured metadata
    public func log(
        _ level: LogLevel,
        _ category: LogCategory,
        _ message: String,
        metadata: [String: String]? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata
        )

        // Try to deduplicate with recent entries
        if let lastEntry = logEntries.last,
           lastEntry.canDeduplicate(with: entry),
           Date().timeIntervalSince(lastEntry.timestamp) < deduplicationWindow {
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
    }

    /// Convenience methods for each log level
    public func trace(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil) {
        log(.trace, category, message, metadata: metadata)
    }

    public func debug(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil) {
        log(.debug, category, message, metadata: metadata)
    }

    public func info(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil) {
        log(.info, category, message, metadata: metadata)
    }

    public func warning(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil) {
        log(.warning, category, message, metadata: metadata)
    }

    public func error(_ category: LogCategory, _ message: String, metadata: [String: String]? = nil) {
        log(.error, category, message, metadata: metadata)
    }

    /// Get all log entries (for the UI)
    public func getEntries() -> [LogEntry] {
        return logEntries
    }

    /// Get entries filtered by level
    public func getEntries(minLevel: LogLevel) -> [LogEntry] {
        return logEntries.filter { $0.level >= minLevel }
    }

    /// Get entries filtered by category
    public func getEntries(category: LogCategory) -> [LogEntry] {
        return logEntries.filter { $0.category == category }
    }

    /// Export logs as formatted text
    public func exportAsText() -> String {
        let header = """
        wBlock Logs Export
        Generated: \(Date())
        Total Entries: \(logEntries.count)
        ════════════════════════════════════════

        """

        let logs = logEntries.map { $0.exportFormat }.joined(separator: "\n\n")
        return header + logs
    }

    /// Clear all log entries
    public func clearLogs() {
        logEntries.removeAll()
        log(.info, .system, "Logs cleared")
    }

    // MARK: - Shared Auto-Update Log Ingestion

    private func sharedAutoUpdateLogURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value)?
            .appendingPathComponent("auto_update.log")
    }

    public func ingestSharedAutoUpdateLog() {
        guard let url = sharedAutoUpdateLogURL(),
              FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8),
              !content.isEmpty else {
            return
        }

        // Parse and add auto-update logs
        let lines = content.split(separator: "\n").map(String.init)
        for line in lines {
            if let telemetry = parseTelemetryLine(line) {
                let event = telemetry["event"] ?? "unknown"
                log(.info, .autoUpdate, "Telemetry: \(event)", metadata: telemetry)
            } else {
                log(.debug, .autoUpdate, line)
            }
        }

        // Clear file after ingestion
        try? FileManager.default.removeItem(at: url)
    }

    private func parseTelemetryLine(_ line: String) -> [String: String]? {
        let body: String
        if let bracketEnd = line.firstIndex(of: "]") {
            let afterTimestamp = line.index(after: bracketEnd)
            body = String(line[afterTimestamp...]).trimmingCharacters(in: .whitespaces)
        } else {
            body = line
        }

        guard body.hasPrefix("telemetry ") else { return nil }
        let payload = body.dropFirst("telemetry ".count)
        var metadata: [String: String] = [:]

        for token in payload.split(separator: " ") {
            guard let separator = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<separator])
            let value = String(token[token.index(after: separator)...])
            metadata[key] = value.replacingOccurrences(of: "_", with: " ")
        }

        return metadata.isEmpty ? nil : metadata
    }
}
