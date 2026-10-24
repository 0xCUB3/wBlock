import Foundation
import os.log

/// Backup policy for regenerable data, never the app-group container itself.
public enum FilterArtifactStorage {
    public static func excludeFromBackup(_ url: URL) {
        do {
            var url = url
            let current = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isExcludedFromBackupKey])
            guard current.isSymbolicLink != true, current.isExcludedFromBackup != true else { return }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            os_log(.error, "Failed to exclude filter artifact from backup at %{public}@: %{public}@", url.path, error.localizedDescription)
        }
    }

    /// Atomic replacement creates a new inode, so set the flag after every write.
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        excludeFromBackup(url)
    }

    static func scratchDirectory(in container: URL) throws -> URL {
        var directory = container
        for component in ["Library", "Caches", "FilterCompilation"] {
            directory.appendPathComponent(component, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
        }
        excludeFromBackup(directory)
        return directory
    }

    /// Only known artifacts are touched. Custom sources and unknown files stay backed up.
    public static func maintain(
        container: URL, generatedFilenames: [String], now: Date = Date()
    ) {
        let manager = FileManager.default
        for name in generatedFilenames where !name.isEmpty && name != "." && name != ".." && !name.contains("/") {
            let url = container.appendingPathComponent(name)
            if manager.fileExists(atPath: url.path) { excludeFromBackup(url) }
        }
        let engine = container.appendingPathComponent(".webext", isDirectory: true)
        if manager.fileExists(atPath: engine.path) { excludeFromBackup(engine) }
        let scratch = try? scratchDirectory(in: container)
        // A killed process cannot run defer. Leave recent files alone, including
        // inputs belonging to another process. Never recurse into unknown paths.
        for directory in [container, engine] + (scratch.map { [$0] } ?? []) {
            guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { continue }
            guard let entries = try? manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .contentModificationDateKey]
            ) else { continue }
            for url in entries {
                guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .contentModificationDateKey]),
                      values.isSymbolicLink != true else { continue }
                let name = url.lastPathComponent
                let isInput = name.hasPrefix("temp_skula.wBlock.wBlock-") && name.hasSuffix(".txt")
                    && UUID(uuidString: String(name.dropLast(4).suffix(36))) != nil
                    && values.isRegularFile == true
                let isEngine = name.hasPrefix("engine-rebuild-")
                    && UUID(uuidString: String(name.dropFirst("engine-rebuild-".count))) != nil
                    && values.isDirectory == true
                guard isInput || isEngine else { continue }
                excludeFromBackup(url)
                guard let modified = values.contentModificationDate,
                      now.timeIntervalSince(modified) > 7 * 24 * 60 * 60 else { continue }
                do { try manager.removeItem(at: url) }
                catch { os_log(.error, "Failed to remove stale filter artifact at %{public}@: %{public}@", url.path, error.localizedDescription) }
            }
        }
    }
}
