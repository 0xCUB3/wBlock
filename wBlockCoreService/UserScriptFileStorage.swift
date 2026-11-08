import Foundation
import Darwin

/// Shared files precede process-private fallbacks so app updates reach extensions.
enum UserScriptFileStorage {
    private final class CachedRead {
        let identity: [Int64]
        let value: Any
        init(_ identity: [Int64], _ value: Any) { self.identity = identity; self.value = value }
    }
    private static let reads: NSCache<NSURL, CachedRead> = {
        let cache = NSCache<NSURL, CachedRead>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    // ctime detects in-place writes even if a writer restores mtime; inode and
    // device detect atomic replacements. Missing files never hit the cache.
    private static func identity(_ url: URL) -> [Int64]? {
        var info = stat()
        guard url.withUnsafeFileSystemRepresentation({ fstatat(AT_FDCWD, $0!, &info, 0) }) == 0 else { return nil }
        return [Int64(info.st_dev), Int64(bitPattern: info.st_ino), info.st_size,
                Int64(info.st_mtimespec.tv_sec), Int64(info.st_mtimespec.tv_nsec),
                Int64(info.st_ctimespec.tv_sec), Int64(info.st_ctimespec.tv_nsec)]
    }

    /// Missing copies are already removed; try every artifact even if one fails.
    nonisolated static func remove(fileNames: [String], directories: [URL], fileManager: FileManager = .default) throws {
        var firstError: Error?
        for directory in directories {
            for name in fileNames {
                do {
                    try fileManager.removeItem(at: directory.appendingPathComponent(name))
                } catch {
                    let error = error as NSError
                    if !(error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError), firstError == nil {
                        firstError = error
                    }
                }
            }
        }
        if let firstError { throw firstError }
    }

    /// Removes the source and sidecars of scripts the store no longer lists, such
    /// as those left behind by a data reset. Files written in the last week stay:
    /// another process may have saved a script it has not recorded yet.
    nonisolated static func removeOrphans(keeping ids: Set<UUID>, directories: [URL], now: Date = Date()) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        for directory in directories {
            for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? [] {
                let name = url.lastPathComponent
                guard name.dropFirst(36).first == ".", let id = UUID(uuidString: String(name.prefix(36))), !ids.contains(id),
                      let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                      let modified = values.contentModificationDate, now.timeIntervalSince(modified) > 7 * 24 * 60 * 60
                else { continue }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    nonisolated static func read<Value>(
        fileName: String,
        directories: [URL],
        decode: (Data) -> Value?
    ) -> Value? {
        for (index, directory) in directories.enumerated() {
            let file = directory.appendingPathComponent(fileName)
            guard let stamp = identity(file) else { continue }
            let value: Value
            if let cached = reads.object(forKey: file as NSURL), cached.identity == stamp,
               let decoded = cached.value as? Value {
                value = decoded
            } else {
                guard let data = try? Data(contentsOf: file), let decoded = decode(data) else { continue }
                value = decoded
                if identity(file) == stamp {
                    reads.setObject(CachedRead(stamp, value), forKey: file as NSURL, cost: data.count)
                }
            }
            if index > 0, let shared = directories.first {
                // Migrate legacy private files only when no shared file exists.
                // copyItem refuses to overwrite a concurrent app update.
                try? FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: file, to: shared.appendingPathComponent(fileName))
            }
            return value
        }
        return nil
    }
}
