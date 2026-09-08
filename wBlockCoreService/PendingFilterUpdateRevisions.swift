//
//  PendingFilterUpdateRevisions.swift
//  wBlockCoreService
//

import Darwin
import CryptoKit
import Foundation

/// Persistent record of downloaded filter source files that have not yet been
/// acknowledged by a successful Safari apply. Each write receives a token;
/// acknowledgements remove only the exact tokens captured before apply so a
/// newer download racing with an older apply stays pending.
public enum PendingFilterUpdateRevisions {
    public struct Revision: Codable, Equatable, Sendable {
        public let filterID: String
        public let token: String
        public let downloadedAt: TimeInterval
        public let etag: String?
        public let lastModified: String?
        public let version: String?
        public let sourceSHA256: String?
        public let sourceFilename: String?
        public let stagedFilename: String?

        public init(
            filterID: String,
            token: String,
            downloadedAt: TimeInterval,
            etag: String?,
            lastModified: String?,
            version: String?,
            sourceSHA256: String? = nil,
            sourceFilename: String? = nil,
            stagedFilename: String? = nil
        ) {
            self.filterID = filterID
            self.token = token
            self.downloadedAt = downloadedAt
            self.etag = etag
            self.lastModified = lastModified
            self.version = version
            self.sourceSHA256 = sourceSHA256
            self.sourceFilename = sourceFilename
            self.stagedFilename = stagedFilename
        }
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        public let tokensByFilterID: [String: String]

        public init(tokensByFilterID: [String: String]) {
            self.tokensByFilterID = tokensByFilterID
        }

        public var isEmpty: Bool { tokensByFilterID.isEmpty }
    }

    private struct State: Codable, Equatable {
        var revisionsByFilterID: [String: Revision]
    }

    public static let filename = "pending-filter-update-revisions.json"

    private static let lock = NSLock()
    private static let fileLockTimeoutSeconds: TimeInterval = 2
    private static let fileLockRetryMicroseconds: useconds_t = 20_000

    public static func storeURL(groupIdentifier: String = GroupIdentifier.shared.value) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent(filename, isDirectory: false)
    }

    @discardableResult
    public static func markDownloaded(
        filterID: String,
        etag: String? = nil,
        lastModified: String? = nil,
        version: String? = nil,
        sourceSHA256: String? = nil,
        sourceFilename: String? = nil,
        stagedFilename: String? = nil,
        groupIdentifier: String = GroupIdentifier.shared.value,
        publish: () throws -> Void = {}
    ) -> Revision? {
        guard let url = storeURL(groupIdentifier: groupIdentifier) else { return nil }
        return markDownloaded(
            filterID: filterID,
            etag: etag,
            lastModified: lastModified,
            version: version,
            sourceSHA256: sourceSHA256,
            sourceFilename: sourceFilename,
            stagedFilename: stagedFilename,
            storeURL: url,
            publish: publish
        )
    }

    @discardableResult
    public static func markDownloaded(
        filterID: String,
        etag: String? = nil,
        lastModified: String? = nil,
        version: String? = nil,
        sourceSHA256: String? = nil,
        sourceFilename: String? = nil,
        stagedFilename: String? = nil,
        token: String = UUID().uuidString,
        now: TimeInterval = Date().timeIntervalSince1970,
        storeURL: URL,
        publish: () throws -> Void = {}
    ) -> Revision? {
        let revision = Revision(
            filterID: filterID,
            token: token,
            downloadedAt: now,
            etag: etag,
            lastModified: lastModified,
            version: version,
            sourceSHA256: sourceSHA256,
            sourceFilename: sourceFilename,
            stagedFilename: stagedFilename
        )
        lock.lock()
        defer { lock.unlock() }
        do {
            try withFileLock(for: storeURL) {
                let previous = loadStateUnlocked(from: storeURL)
                var next = previous
                next.revisionsByFilterID[filterID] = revision
                try saveStateUnlocked(next, to: storeURL)
                do {
                    // Keep apply snapshots blocked until the matching source is visible.
                    try publish()
                } catch {
                    try saveStateUnlocked(previous, to: storeURL)
                    throw error
                }
            }
            return revision
        } catch {
            return nil
        }
    }

    public static func contains(
        filterID: String,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> Bool {
        guard let url = storeURL(groupIdentifier: groupIdentifier) else { return false }
        return contains(filterID: filterID, storeURL: url)
    }

    public static func contains(filterID: String, storeURL: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return (try? withFileLock(for: storeURL) {
            loadStateUnlocked(from: storeURL).revisionsByFilterID[filterID] != nil
        }) ?? false
    }

    public static func pendingFilterIDs(
        selectedFilterIDs: Set<String>,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> Set<String> {
        guard let url = storeURL(groupIdentifier: groupIdentifier) else { return [] }
        return pendingFilterIDs(selectedFilterIDs: selectedFilterIDs, storeURL: url)
    }

    public static func pendingFilterIDs(selectedFilterIDs: Set<String>, storeURL: URL) -> Set<String> {
        guard !selectedFilterIDs.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return (try? withFileLock(for: storeURL) {
            let storedIDs = Set(loadStateUnlocked(from: storeURL).revisionsByFilterID.keys)
            return storedIDs.intersection(selectedFilterIDs)
        }) ?? []
    }

    public static func snapshot(
        filterIDs: Set<String>,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> Snapshot {
        guard let url = storeURL(groupIdentifier: groupIdentifier) else {
            return Snapshot(tokensByFilterID: [:])
        }
        return snapshot(filterIDs: filterIDs, storeURL: url)
    }

    public static func snapshot(filterIDs: Set<String>, storeURL: URL) -> Snapshot {
        guard !filterIDs.isEmpty else { return Snapshot(tokensByFilterID: [:]) }
        lock.lock()
        defer { lock.unlock() }
        return (try? withFileLock(for: storeURL) {
            let revisions = loadStateUnlocked(from: storeURL).revisionsByFilterID
            let captured = revisions.reduce(into: [String: String]()) { result, item in
                guard filterIDs.contains(item.key) else { return }
                result[item.key] = item.value.token
            }
            return Snapshot(tokensByFilterID: captured)
        }) ?? Snapshot(tokensByFilterID: [:])
    }

    /// Captures only revisions whose published source matches the revision digest.
    /// If a process died after journaling but before source replacement, a matching
    /// staged file is atomically promoted before the token is captured.
    public static func snapshotPublished(
        filterIDs: Set<String>,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> Snapshot {
        guard let url = storeURL(groupIdentifier: groupIdentifier) else {
            return Snapshot(tokensByFilterID: [:])
        }
        return snapshotPublished(filterIDs: filterIDs, storeURL: url)
    }

    public static func snapshotPublished(filterIDs: Set<String>, storeURL: URL) -> Snapshot {
        guard !filterIDs.isEmpty else { return Snapshot(tokensByFilterID: [:]) }
        lock.lock()
        defer { lock.unlock() }
        return (try? withFileLock(for: storeURL) {
            var state = loadStateUnlocked(from: storeURL)
            var captured: [String: String] = [:]
            var prunedLegacyRevision = false
            for filterID in filterIDs {
                guard let revision = state.revisionsByFilterID[filterID] else { continue }
                guard hasSourceIdentity(revision) else {
                    state.revisionsByFilterID.removeValue(forKey: filterID)
                    prunedLegacyRevision = true
                    continue
                }
                guard ensurePublishedUnlocked(revision, storeURL: storeURL) else { continue }
                captured[filterID] = revision.token
            }
            if prunedLegacyRevision {
                try saveStateUnlocked(state, to: storeURL)
            }
            return Snapshot(tokensByFilterID: captured)
        }) ?? Snapshot(tokensByFilterID: [:])
    }

    public static func isPublished(
        filterID: String,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> Bool {
        guard let url = storeURL(groupIdentifier: groupIdentifier) else { return false }
        return isPublished(filterID: filterID, storeURL: url)
    }

    public static func isPublished(filterID: String, storeURL: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return (try? withFileLock(for: storeURL) {
            var state = loadStateUnlocked(from: storeURL)
            guard let revision = state.revisionsByFilterID[filterID] else {
                return false
            }
            guard hasSourceIdentity(revision) else {
                state.revisionsByFilterID.removeValue(forKey: filterID)
                try saveStateUnlocked(state, to: storeURL)
                return false
            }
            return ensurePublishedUnlocked(revision, storeURL: storeURL)
        }) ?? false
    }

    public static func publishedRevision(
        filterID: String,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> Revision? {
        guard let url = storeURL(groupIdentifier: groupIdentifier) else { return nil }
        return publishedRevision(filterID: filterID, storeURL: url)
    }

    public static func publishedRevision(filterID: String, storeURL: URL) -> Revision? {
        lock.lock()
        defer { lock.unlock() }
        return try? withFileLock(for: storeURL) {
            var state = loadStateUnlocked(from: storeURL)
            guard let revision = state.revisionsByFilterID[filterID] else { return nil }
            guard hasSourceIdentity(revision) else {
                state.revisionsByFilterID.removeValue(forKey: filterID)
                try saveStateUnlocked(state, to: storeURL)
                return nil
            }
            guard ensurePublishedUnlocked(revision, storeURL: storeURL) else { return nil }
            return revision
        }
    }

    public static func acknowledge(
        _ snapshot: Snapshot,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) {
        guard let url = storeURL(groupIdentifier: groupIdentifier) else { return }
        acknowledge(snapshot, storeURL: url)
    }

    public static func acknowledge(_ snapshot: Snapshot, storeURL: URL) {
        guard !snapshot.isEmpty else { return }
        try? lockedUpdate(storeURL: storeURL) { state in
            for (filterID, token) in snapshot.tokensByFilterID {
                guard state.revisionsByFilterID[filterID]?.token == token else { continue }
                state.revisionsByFilterID.removeValue(forKey: filterID)
            }
        }
    }

    public static func remove(
        filterIDs: Set<String>,
        groupIdentifier: String = GroupIdentifier.shared.value
    ) {
        guard let url = storeURL(groupIdentifier: groupIdentifier) else { return }
        remove(filterIDs: filterIDs, storeURL: url)
    }

    public static func remove(filterIDs: Set<String>, storeURL: URL) {
        guard !filterIDs.isEmpty else { return }
        try? lockedUpdate(storeURL: storeURL) { state in
            for filterID in filterIDs {
                state.revisionsByFilterID.removeValue(forKey: filterID)
            }
        }
    }

    public static func load(storeURL: URL) -> [String: Revision] {
        lock.lock()
        defer { lock.unlock() }
        return (try? withFileLock(for: storeURL) {
            loadStateUnlocked(from: storeURL).revisionsByFilterID
        }) ?? [:]
    }

    public static func clear(groupIdentifier: String = GroupIdentifier.shared.value) {
        guard let url = storeURL(groupIdentifier: groupIdentifier) else { return }
        clear(storeURL: url)
    }

    public static func clear(storeURL: URL) {
        lock.lock()
        defer { lock.unlock() }
        try? withFileLock(for: storeURL) {
            try? FileManager.default.removeItem(at: storeURL)
        }
    }

    private static func lockedUpdate(storeURL: URL, update: (inout State) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        try withFileLock(for: storeURL) {
            var state = loadStateUnlocked(from: storeURL)
            update(&state)
            try saveStateUnlocked(state, to: storeURL)
        }
    }

    private static func withFileLock<T>(for storeURL: URL, _ body: () throws -> T) throws -> T {
        let lockURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent(".\(filename).lock", isDirectory: false)
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            let error = errno
            throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
        }
        do {
            try lockDescriptor(descriptor)
        } catch {
            close(descriptor)
            throw error
        }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        return try body()
    }

    private static func lockDescriptor(_ descriptor: Int32) throws {
        let deadline = Date().timeIntervalSince1970 + fileLockTimeoutSeconds
        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                return
            }
            let error = errno
            guard error == EWOULDBLOCK || error == EAGAIN else {
                throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
            }
            guard Date().timeIntervalSince1970 < deadline else {
                throw POSIXError(.ETIMEDOUT)
            }
            usleep(fileLockRetryMicroseconds)
        }
    }

    private static func loadStateUnlocked(from url: URL) -> State {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else {
            return State(revisionsByFilterID: [:])
        }
        return state
    }

    private static func saveStateUnlocked(_ state: State, to url: URL) throws {
        if state.revisionsByFilterID.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
    }

    private static func ensurePublishedUnlocked(_ revision: Revision, storeURL: URL) -> Bool {
        guard let expectedDigest = revision.sourceSHA256?.lowercased(), !expectedDigest.isEmpty,
              let sourceFilename = safeFilename(revision.sourceFilename) else {
            return false
        }
        let directory = storeURL.deletingLastPathComponent()
        let sourceURL = directory.appendingPathComponent(sourceFilename, isDirectory: false)
        if sha256Hex(of: sourceURL) == expectedDigest {
            return true
        }

        guard let stagedFilename = safeFilename(revision.stagedFilename) else { return false }
        let stagedURL = directory.appendingPathComponent(stagedFilename, isDirectory: false)
        guard sha256Hex(of: stagedURL) == expectedDigest else { return false }
        do {
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                _ = try FileManager.default.replaceItemAt(sourceURL, withItemAt: stagedURL)
            } else {
                try FileManager.default.moveItem(at: stagedURL, to: sourceURL)
            }
            let baselineURL = directory.appendingPathComponent(
                "diff-baseline-\(sourceFilename)",
                isDirectory: false
            )
            try? FileManager.default.removeItem(at: baselineURL)
            return sha256Hex(of: sourceURL) == expectedDigest
        } catch {
            return false
        }
    }

    private static func hasSourceIdentity(_ revision: Revision) -> Bool {
        revision.sourceSHA256?.isEmpty == false && safeFilename(revision.sourceFilename) != nil
    }

    private static func safeFilename(_ value: String?) -> String? {
        guard let value, !value.isEmpty,
              value == URL(fileURLWithPath: value).lastPathComponent,
              !value.contains("/") else { return nil }
        return value
    }

    private static func sha256Hex(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while true {
                let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
                if data.isEmpty { break }
                hasher.update(data: data)
            }
        } catch {
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
