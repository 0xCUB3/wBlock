import CryptoKit
import Foundation
import os.log
internal import WBEngine

/// The per-page engine the wBlock Scripts extension queries: the rules Safari
/// cannot enforce natively (procedural cosmetics, `:style`, scriptlets),
/// serialized by the app and read by the extension from the app group.
enum FilterEngineStore {
    private static let directoryName = ".wbe"
    private static let engineFileName = "engine.snapshot"
    private static let lockFileName = "publish.lock"
    private static let latestRequestFileName = "latest.request"
    /// The engine AdGuard's FilterEngine kept here before wBlock 4.
    private static let legacyDirectoryName = ".webext"
    private static let lockTimeout: TimeInterval = 10

    private struct Snapshot: Codable {
        let fingerprint: String
        let timestamp: Int64
        let engine: Data
    }

    enum PublishError: Error {
        case containerNotFound
        case lockUnavailable
    }

    /// Builds and publishes the engine for `runtimeRules`. Unchanged rules are
    /// not rebuilt; a publish that a newer one overtook is abandoned.
    static func publish(runtimeRules: String, groupIdentifier: String) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else { throw PublishError.containerNotFound }
        let directory = containerURL.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FilterArtifactStorage.excludeFromBackup(directory)
        try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(legacyDirectoryName))

        #if os(iOS)
        // Holding an app group flock across suspension gets the process killed
        // (0xDEAD10CC).
        let shield = SuspensionShield(reason: "wBlock engine publish")
        defer { shield.release() }
        #endif

        let request = UUID().uuidString
        try withLock(in: directory) {
            try Data(request.utf8).write(to: directory.appendingPathComponent(latestRequestFileName), options: .atomic)
        }
        // The serialized format belongs to the engine version, so it is part of
        // the fingerprint as well as the rules.
        let fingerprint = SHA256.hash(data: Data((SafariVersionDetection.compilerIdentity + "\n" + runtimeRules).utf8))
            .map { String(format: "%02x", $0) }.joined()
        if readSnapshot(in: directory)?.fingerprint == fingerprint {
            return
        }
        let engine = try measure(label: "Building filter engine") {
            try WBEngine.buildEngine(runtimeRules: runtimeRules)
        }
        let published = try withLock(in: directory) {
            let latest = try? String(contentsOf: directory.appendingPathComponent(latestRequestFileName), encoding: .utf8)
            guard latest == request else { return false }
            let timestamp = max(Int64(Date().timeIntervalSince1970 * 1000), (readSnapshot(in: directory)?.timestamp ?? 0) + 1)
            let snapshot = Snapshot(fingerprint: fingerprint, timestamp: timestamp, engine: engine)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(snapshot).write(to: directory.appendingPathComponent(engineFileName), options: .atomic)
            return true
        }
        os_log(.info, published ? "Published filter engine: %d bytes" : "Abandoned filter engine (%d bytes) for a newer publish", engine.count)
    }

    /// Whether an engine has been published, so the Scripts extension has one.
    static func hasPublishedEngine(groupIdentifier: String) -> Bool {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupIdentifier
        ) else { return false }
        let directory = containerURL.appendingPathComponent(directoryName, isDirectory: true)
        return readSnapshot(in: directory) != nil
    }

    /// The per-page payload for `url` (see Packages/wblock-engine/docs/BRIEF.md),
    /// or nil when no engine has been published.
    static func lookup(url: URL, groupIdentifier: String) throws -> [String: Any]? {
        try WebExtensionGate.shared.withLock {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupIdentifier
            ) else { throw PublishError.containerNotFound }
            let directory = containerURL.appendingPathComponent(directoryName, isDirectory: true)
            // Each publish atomically replaces the file, so its file number
            // changes; the snapshot is read and decoded only then.
            let file = directory.appendingPathComponent(engineFileName)
            guard let fileNumber = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.systemFileNumber] as? Int
            else { return nil }
            if cached?.fileNumber != fileNumber {
                guard let snapshot = readSnapshot(in: directory) else { return nil }
                cached = (fileNumber, snapshot.timestamp, try WBEngine.Engine(data: snapshot.engine))
            }
            guard let (_, timestamp, engine) = cached,
                  var payload = try JSONSerialization.jsonObject(with: engine.lookup(url: url.absoluteString)) as? [String: Any]
            else { return nil }
            payload["css"] = payload.removeValue(forKey: "hide")
            payload["engineTimestamp"] = timestamp
            return payload
        }
    }

    /// The engine the extension process last loaded. Guarded by WebExtensionGate.
    nonisolated(unsafe) private static var cached: (fileNumber: Int, timestamp: Int64, engine: WBEngine.Engine)?

    private static func readSnapshot(in directory: URL) -> Snapshot? {
        (try? Data(contentsOf: directory.appendingPathComponent(engineFileName)))
            .flatMap { try? PropertyListDecoder().decode(Snapshot.self, from: $0) }
    }

    private static func withLock<T>(in directory: URL, _ body: () throws -> T) throws -> T {
        guard let lock = FileLock(filePath: directory.appendingPathComponent(lockFileName).path),
              lock.lock(before: Date().addingTimeInterval(lockTimeout))
        else { throw PublishError.lockUnavailable }
        defer { lock.unlock() }
        return try body()
    }
}
