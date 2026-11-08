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
    /// A `sibling` that starts with the same bytes, such as a blocker's base rules
    /// and its output, shares the disk blocks of that prefix with the new file.
    static func write(_ data: Data, to url: URL, sharingBlocksWith sibling: URL? = nil) throws {
        if sibling.flatMap({ try? writeClone(data, to: url, from: $0) }) != true {
            try data.write(to: url, options: .atomic)
        }
        excludeFromBackup(url)
    }

    /// Clones `sibling` and rewrites the clone from the first differing byte on.
    /// Writers replace these files atomically, so the opened file cannot change
    /// between the comparison and the clone.
    private static func writeClone(_ data: Data, to url: URL, from sibling: URL) throws -> Bool {
        let source = open(sibling.path, O_RDONLY)
        guard source >= 0 else { return false }
        defer { close(source) }
        var info = stat()
        guard fstat(source, &info) == 0, info.st_size > 0,
              let mapped = mmap(nil, Int(info.st_size), PROT_READ, MAP_PRIVATE, source, 0), mapped != MAP_FAILED
        else { return false }
        let shared = data.withUnsafeBytes { bytes -> Int in
            let count = min(bytes.count, Int(info.st_size))
            var offset = 0
            while offset < count, memcmp(bytes.baseAddress! + offset, mapped + offset, min(1 << 16, count - offset)) == 0 {
                offset += 1 << 16
            }
            offset = min(offset, count)
            while offset < count, bytes[offset] == mapped.load(fromByteOffset: offset, as: UInt8.self) { offset += 1 }
            return offset
        }
        munmap(mapped, Int(info.st_size))
        // Below a few blocks a clone saves nothing.
        guard shared >= 1 << 16 else { return false }
        let directory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clone = directory.appendingPathComponent(url.lastPathComponent)
        guard fclonefileat(source, AT_FDCWD, clone.path, 0) == 0 else { return false }
        let handle = try FileHandle(forWritingTo: clone)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(shared))
        try handle.write(contentsOf: data.dropFirst(shared))
        return rename(clone.path, url.path) == 0
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
