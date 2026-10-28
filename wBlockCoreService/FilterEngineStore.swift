import CryptoKit
import Foundation
import os.log
internal import WBEngine

/// The per-page engine the wBlock Scripts extension queries: the rules Safari
/// cannot enforce natively (procedural cosmetics, `:style`, scriptlets),
/// serialized by the app and read by the extension from the app group.
enum FilterEngineStore {
    private static let directoryName = ".wbe"
    private static let engineFileName = "engine.bin"
    private static let metaFileName = "engine.json"
    private static let lockFileName = "publish.lock"
    private static let latestRequestFileName = "latest.request"
    /// The engine AdGuard's FilterEngine kept here before wBlock 4.
    private static let legacyDirectoryName = ".webext"
    private static let lockTimeout: TimeInterval = 10

    private struct Meta: Codable {
        let fingerprint: String
        let timestamp: Int64
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
        if readMeta(in: directory)?.fingerprint == fingerprint,
           FileManager.default.fileExists(atPath: directory.appendingPathComponent(engineFileName).path) {
            return
        }
        let engine = try measure(label: "Building filter engine") {
            try WBEngine.buildEngine(runtimeRules: runtimeRules)
        }
        let published = try withLock(in: directory) {
            let latest = try? String(contentsOf: directory.appendingPathComponent(latestRequestFileName), encoding: .utf8)
            guard latest == request else { return false }
            try engine.write(to: directory.appendingPathComponent(engineFileName), options: .atomic)
            let meta = Meta(fingerprint: fingerprint, timestamp: Int64(Date().timeIntervalSince1970 * 1000))
            try JSONEncoder().encode(meta).write(to: directory.appendingPathComponent(metaFileName), options: .atomic)
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
        return readMeta(in: directory) != nil
            && FileManager.default.fileExists(atPath: directory.appendingPathComponent(engineFileName).path)
    }

    /// The per-page payload for `url` (see Packages/wblock-engine/docs/BRIEF.md),
    /// or nil when no engine has been published.
    static func lookup(url: URL, groupIdentifier: String) throws -> [String: Any]? {
        try WebExtensionGate.shared.withLock {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupIdentifier
            ) else { throw PublishError.containerNotFound }
            let directory = containerURL.appendingPathComponent(directoryName, isDirectory: true)
            guard let meta = readMeta(in: directory) else { return nil }
            if cached?.timestamp != meta.timestamp {
                let data = try Data(contentsOf: directory.appendingPathComponent(engineFileName))
                cached = (meta.timestamp, try WBEngine.Engine(data: data))
            }
            guard let (timestamp, engine) = cached,
                  var payload = try JSONSerialization.jsonObject(with: engine.lookup(url: url.absoluteString)) as? [String: Any]
            else { return nil }
            payload["css"] = payload.removeValue(forKey: "hide")
            payload["engineTimestamp"] = timestamp
            return payload
        }
    }

    /// The engine the extension process last loaded. Guarded by WebExtensionGate.
    nonisolated(unsafe) private static var cached: (timestamp: Int64, engine: WBEngine.Engine)?

    private static func readMeta(in directory: URL) -> Meta? {
        (try? Data(contentsOf: directory.appendingPathComponent(metaFileName)))
            .flatMap { try? JSONDecoder().decode(Meta.self, from: $0) }
    }

    private static func withLock<T>(in directory: URL, _ body: () throws -> T) throws -> T {
        guard let lock = FileLock(filePath: directory.appendingPathComponent(lockFileName).path),
              lock.lock(before: Date().addingTimeInterval(lockTimeout))
        else { throw PublishError.lockUnavailable }
        defer { lock.unlock() }
        return try body()
    }
}
