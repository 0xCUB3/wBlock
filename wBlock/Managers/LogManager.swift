//
//  LogManager.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//

import Foundation
import os.log

class LogManager {
    private let logger = Logger(subsystem: "com.0xcube.wBlock", category: "FilterListManager")
    private(set) var logs: String = ""
    private let sharedContainerIdentifier = "group.com.0xcube.wBlock"
    private let maxLogSize = 100_000 // Maximum number of characters to keep in the log

    /// Appends a message to the logs and returns the updated logs
    @discardableResult
    func appendLog(_ message: String) -> String {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"

        // Add the new log entry to the beginning for easier reading of recent logs
        logs = logEntry + "\n" + logs

        // Trim logs if they get too large
        if logs.count > maxLogSize {
            if let index = logs.lastIndex(of: "\n", offsetBy: maxLogSize, limitedBy: logs.endIndex) {
                logs = String(logs[..<index])
            } else {
                logs = String(logs.prefix(maxLogSize))
            }
        }

        saveLogsToFile()
        logger.info("\(message, privacy: .public)")
        return logs
    }

    /// Clears the logs and returns the empty string
    @discardableResult
    func clearLogs() -> String {
        logs = ""
        saveLogsToFile()
        return logs
    }

    /// Saves logs to a file in the shared container
    private func saveLogsToFile() {
        guard let containerURL = getSharedContainerURL() else { return }
        let fileURL = containerURL.appendingPathComponent("logs.txt")

        do {
            try logs.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Error saving logs: \(error)")
            logger.error("Failed to save logs to file: \(error.localizedDescription)")
        }
    }

    /// Loads logs from the shared container and returns them
    @discardableResult
    func loadLogsFromFile() -> String {
        guard let containerURL = getSharedContainerURL() else { return logs }
        let fileURL = containerURL.appendingPathComponent("logs.txt")

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                logs = try String(contentsOf: fileURL, encoding: .utf8)
            } else {
                logs = "No log file found."
                saveLogsToFile()
            }
        } catch {
            print("Error loading logs: \(error)")
            logger.error("Failed to load logs from file: \(error.localizedDescription)")
            logs = "Error loading logs: \(error.localizedDescription)"
        }

        return logs
    }

    /// Exports logs to a file at the specified URL
    func exportLogs(to url: URL) -> Bool {
        do {
            try logs.write(to: url, atomically: true, encoding: .utf8)
            logger.info("Logs exported successfully to \(url.path)")
            return true
        } catch {
            logger.error("Failed to export logs: \(error.localizedDescription)")
            return false
        }
    }

    /// Retrieves the shared container URL
    private func getSharedContainerURL() -> URL? {
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier)
    }

    /// Adds a separator line to the logs
    func addSeparator() {
        appendLog("----------------------------------------")
    }

    /// Logs an error with a specific category
    func logError(_ message: String, category: String = "General") {
        let errorMessage = "[ERROR][\(category)] \(message)"
        appendLog(errorMessage)
        logger.error("\(errorMessage, privacy: .public)")
    }

    /// Logs a warning with a specific category
    func logWarning(_ message: String, category: String = "General") {
        let warningMessage = "[WARNING][\(category)] \(message)"
        appendLog(warningMessage)
        logger.warning("\(warningMessage, privacy: .public)")
    }

    /// Logs information with a specific category
    func logInfo(_ message: String, category: String = "General") {
        let infoMessage = "[INFO][\(category)] \(message)"
        appendLog(infoMessage)
        logger.info("\(infoMessage, privacy: .public)")
    }

    /// Logs a debug message with a specific category (only in debug builds)
    func logDebug(_ message: String, category: String = "General") {
        #if DEBUG
        let debugMessage = "[DEBUG][\(category)] \(message)"
        appendLog(debugMessage)
        logger.debug("\(debugMessage, privacy: .public)")
        #endif
    }
}

extension String {
    /// Helper method to find the last occurrence of a character with an offset
    func lastIndex(of element: Character, offsetBy: Int, limitedBy: String.Index) -> String.Index? {
        var count = 0
        var index = self.endIndex

        while count < offsetBy {
            guard let newIndex = self.lastIndex(of: element, in: self.startIndex..<index) else {
                return nil
            }

            index = newIndex
            count += 1

            if index <= limitedBy {
                return nil
            }
        }

        return index
    }

    /// Helper method to find the last occurrence of a character in a range
    func lastIndex(of element: Character, in range: Range<String.Index>) -> String.Index? {
        var index = range.upperBound
        while index > range.lowerBound {
            index = self.index(before: index)
            if self[index] == element {
                return index
            }
        }
        return nil
    }
}
