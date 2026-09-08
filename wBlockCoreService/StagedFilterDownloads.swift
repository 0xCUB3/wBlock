//
//  StagedFilterDownloads.swift
//  wBlockCoreService
//

import Darwin
import Foundation

/// Marker left in the app group when the Safari extension has downloaded
/// filter list files but could not rebuild the blockers (#528). The next
/// app-side auto-update run rebuilds from these files and clears it. An
/// empty ID list means "staging started, rebuild everything selected", which
/// covers the extension dying between a file write and the metadata save.
public enum StagedFilterDownloads {
    public struct Marker: Codable, Equatable, Sendable {
        public var filterIDs: [String]
        public var stagedAt: TimeInterval
        public var generation: String?

        public init(filterIDs: [String], stagedAt: TimeInterval, generation: String? = nil) {
            self.filterIDs = filterIDs
            self.stagedAt = stagedAt
            self.generation = generation
        }
    }

    public static let filename = "staged-filter-updates.json"
    private static let lock = NSLock()

    static func url(groupIdentifier: String = GroupIdentifier.shared.value) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent(filename, isDirectory: false)
    }

    public static func load(groupIdentifier: String = GroupIdentifier.shared.value) -> Marker? {
        guard let url = url(groupIdentifier: groupIdentifier) else { return nil }
        return load(storeURL: url)
    }

    public static func load(storeURL: URL) -> Marker? {
        withLock(storeURL: storeURL) {
            let data = try Data(contentsOf: storeURL)
            return try JSONDecoder().decode(Marker.self, from: data)
        }
    }

    @discardableResult
    public static func save(
        filterIDs: [String],
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> Marker? {
        guard let url = url(groupIdentifier: groupIdentifier) else { return nil }
        return save(filterIDs: filterIDs, storeURL: url)
    }

    @discardableResult
    public static func save(filterIDs: [String], storeURL: URL) -> Marker? {
        let marker = Marker(
            filterIDs: filterIDs,
            stagedAt: Date().timeIntervalSince1970,
            generation: UUID().uuidString
        )
        return withLock(storeURL: storeURL) {
            let data = try JSONEncoder().encode(marker)
            try data.write(to: storeURL, options: .atomic)
            return marker
        }
    }

    public static func clear(groupIdentifier: String = GroupIdentifier.shared.value) {
        guard let url = url(groupIdentifier: groupIdentifier) else { return }
        clear(storeURL: url)
    }

    public static func clear(storeURL: URL) {
        _ = withLock(storeURL: storeURL) {
            try? FileManager.default.removeItem(at: storeURL)
            return true
        }
    }

    @discardableResult
    public static func clear(
        ifMatches marker: Marker,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> Bool {
        guard let url = url(groupIdentifier: groupIdentifier) else { return false }
        return clear(ifMatches: marker, storeURL: url)
    }

    @discardableResult
    public static func clear(ifMatches marker: Marker, storeURL: URL) -> Bool {
        withLock(storeURL: storeURL) {
            guard let current = loadUnlocked(storeURL: storeURL), matches(current, marker) else {
                return false
            }
            do {
                try FileManager.default.removeItem(at: storeURL)
                return true
            } catch {
                return false
            }
        } ?? false
    }

    private static func matches(_ lhs: Marker, _ rhs: Marker) -> Bool {
        if let generation = lhs.generation, let other = rhs.generation {
            return generation == other
        }
        return lhs == rhs
    }

    private static func loadUnlocked(storeURL: URL) -> Marker? {
        guard let data = try? Data(contentsOf: storeURL) else { return nil }
        return try? JSONDecoder().decode(Marker.self, from: data)
    }

    private static func withLock<T>(storeURL: URL, _ operation: () throws -> T) -> T? {
        lock.lock()
        defer { lock.unlock() }
        let lockURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent(".\(filename).lock", isDirectory: false)
        try? FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0, flock(descriptor, LOCK_EX) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            return nil
        }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        return try? operation()
    }
}
