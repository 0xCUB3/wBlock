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

    /// Only known artifacts are touched. Custom sources and unknown files stay backed up.
    public static func maintain(container: URL, generatedFilenames: [String]) {
        let manager = FileManager.default
        for name in generatedFilenames where !name.isEmpty && name != "." && name != ".." && !name.contains("/") {
            let url = container.appendingPathComponent(name)
            if manager.fileExists(atPath: url.path) { excludeFromBackup(url) }
        }
        // The converter before wBlock 4 wrote its inputs here; nothing does now.
        let inputs = ((try? manager.contentsOfDirectory(atPath: container.path)) ?? [])
            .filter { $0.hasPrefix("temp_skula.wBlock.wBlock-") && $0.hasSuffix(".txt") }
        for name in inputs + ["Library/Caches/FilterCompilation"] {
            try? manager.removeItem(at: container.appendingPathComponent(name))
        }
    }
}
