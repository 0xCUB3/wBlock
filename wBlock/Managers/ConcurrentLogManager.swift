//
//  that.swift
//  wBlock
//
//  Created by Alexander Skula on 3/23/25.
//

import Foundation

/// A concurrency‑safe logger actor that collects verbose log entries with improved readability.
/// Each log entry is formatted as multiline block with a header and footer separator.
public actor ConcurrentLogManager {
    
 /// The maximum number of log entries to keep in memory.
    private let maxLogEntries: Int = 10_000
    
    /// In‑memory storage for log entries.
    private var logEntries: [String] = []
    
 /// Shared singleton instance.
    public static let shared = ConcurrentLogManager()
    
 /// Date formatter used for timestamps.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Format including milliseconds.
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    
 /// Formats and appends a log message with detailed metadata.
    ///
    /// - Parameters:
    ///   - message: The message to log.
    ///   - file: The file where this log was generated (automatically filled).
    ///   - function: The function name (automatically filled).
    ///   - line: The line number (automatically filled).
    public func log(_ message: String,
                    file: String = #file,
                    function: String = #function,
                    line: Int = #line) {
        let timestamp = Self.dateFormatter.string(from: Date())
        // Only keep the file name.
        let fileName = (file as NSString).lastPathComponent
        
        // Format the log entry as multiline string.
        let formattedEntry = """
        ─────────────────
        Time: \(timestamp)
        Location: \(fileName):\(line) – \(function)
        Message: \(message)
        ─────────────────
        """
        
 logEntries.append(formattedEntry)
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
        // Also print to the console.
        print(formattedEntry)
    }
    
 /// Returns all log entries as single string.
    public func getAllLogs() -> String {
        logEntries.joined(separator: "\n")
    }
    
 /// Clears all log entries.
    public func clearLogs() {
        logEntries.removeAll()
        // Optionally log that logs were cleared.
        Task {
            await self.log("Logs cleared.")
        }
    }
}
