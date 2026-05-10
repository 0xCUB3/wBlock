import Foundation

actor UserScriptStorageManager {
    static let shared = UserScriptStorageManager()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()
    private let storageFileName = "userscript_gm_storage.json"
    private let versionFileName = "userscript_gm_storage.version"

    private var cachedStorage: [String: [String: String]] = [:]
    private var lastLoadedModificationDate: Date?
    private var lastLoadedVersion: Int64 = 0

    private init() {
        let directoryURL = Self.makeDataDirectoryURL(fileManager: fileManager)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func snapshot(for scriptID: String) async -> [String: String] {
        await refreshFromDiskIfModified()
        return cachedStorage[scriptID] ?? [:]
    }

    func setSerializedValue(_ rawValue: String, forKey key: String, scriptID: String) async -> (ok: Bool, error: String?) {
        guard !scriptID.isEmpty, !key.isEmpty else {
            return (false, "Missing userscript storage key")
        }

        do {
            try mutateStorageAtomically { storage in
                var values = storage[scriptID] ?? [:]
                values[key] = rawValue
                storage[scriptID] = values
            }
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func deleteValue(forKey key: String, scriptID: String) async -> (ok: Bool, error: String?) {
        guard !scriptID.isEmpty, !key.isEmpty else {
            return (false, "Missing userscript storage key")
        }

        do {
            try mutateStorageAtomically { storage in
                guard var values = storage[scriptID] else { return }
                values.removeValue(forKey: key)
                if values.isEmpty {
                    storage.removeValue(forKey: scriptID)
                } else {
                    storage[scriptID] = values
                }
            }
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func reset() async -> (ok: Bool, error: String?) {
        do {
            try removeItemIfExists(at: storageFileURL)
            try removeItemIfExists(at: versionFileURL)
            cachedStorage = [:]
            lastLoadedModificationDate = nil
            lastLoadedVersion = 0
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private var dataDirectoryURL: URL {
        Self.makeDataDirectoryURL(fileManager: fileManager)
    }

    private static func makeDataDirectoryURL(fileManager: FileManager) -> URL {
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value) {
            return containerURL.appendingPathComponent("ProtobufData", isDirectory: true)
        }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return appSupport.appendingPathComponent("wBlock").appendingPathComponent("ProtobufData", isDirectory: true)
    }

    private var storageFileURL: URL {
        dataDirectoryURL.appendingPathComponent(storageFileName)
    }

    private var versionFileURL: URL {
        dataDirectoryURL.appendingPathComponent(versionFileName)
    }

    private func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func modificationDate(for url: URL) -> Date? {
        guard fileExists(at: url) else { return nil }
        return (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func writeData(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func dataVersion(for url: URL) -> Int64 {
        guard fileExists(at: url),
              let rawVersion = try? Data(contentsOf: url),
              let stringVersion = String(data: rawVersion, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let version = Int64(stringVersion) else {
            return 0
        }
        return max(version, 0)
    }

    private func writeDataVersion(_ version: Int64, to url: URL) throws {
        let rawVersion = Data(String(max(version, 0)).utf8)
        try writeData(rawVersion, to: url)
    }

    private func withExclusiveFileLock<T>(for dataURL: URL, _ operation: () throws -> T) throws -> T {
        let directoryURL = dataURL.deletingLastPathComponent()
        if !fileExists(at: directoryURL) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationResult: Result<T, Error>?

        coordinator.coordinate(writingItemAt: directoryURL, options: [], error: &coordinationError) { _ in
            operationResult = Result { try operation() }
        }

        if let operationResult {
            return try operationResult.get()
        }

        if let coordinationError {
            throw coordinationError
        }

        throw NSError(
            domain: "UserScriptStorageManager",
            code: CocoaError.fileWriteUnknown.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "File coordination failed before userscript storage write"]
        )
    }

    private func decodeStorage(from data: Data?) throws -> [String: [String: String]] {
        guard let data, !data.isEmpty else { return [:] }
        return try decoder.decode([String: [String: String]].self, from: data)
    }

    private func removeItemIfExists(at url: URL) throws {
        guard fileExists(at: url) else { return }
        try fileManager.removeItem(at: url)
    }

    @discardableResult
    private func refreshFromDiskIfModified(forceRead: Bool = false) async -> Bool {
        let currentModDate = modificationDate(for: storageFileURL)
        let currentVersion = dataVersion(for: versionFileURL)

        if !forceRead,
           currentModDate == lastLoadedModificationDate,
           currentVersion == lastLoadedVersion {
            return false
        }

        guard let currentModDate else {
            let didChange = !cachedStorage.isEmpty || lastLoadedVersion != 0
            cachedStorage = [:]
            lastLoadedModificationDate = nil
            lastLoadedVersion = 0
            return didChange
        }

        do {
            let rawData = try Data(contentsOf: storageFileURL)
            let decoded = try decodeStorage(from: rawData)
            let didChange = decoded != cachedStorage
            cachedStorage = decoded
            lastLoadedModificationDate = currentModDate
            lastLoadedVersion = currentVersion
            return didChange
        } catch {
            #if DEBUG
            print("[wBlock] Failed to refresh userscript storage from disk: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    private func mutateStorageAtomically(_ mutate: (inout [String: [String: String]]) -> Void) throws {
        try withExclusiveFileLock(for: storageFileURL) {
            let persistedRawData = try? Data(contentsOf: storageFileURL)
            var storage = try decodeStorage(from: persistedRawData)
            mutate(&storage)

            let updatedRawData = try encoder.encode(storage)
            let currentVersion = dataVersion(for: versionFileURL)

            if persistedRawData == updatedRawData {
                cachedStorage = storage
                lastLoadedModificationDate = modificationDate(for: storageFileURL)
                lastLoadedVersion = currentVersion
                return
            }

            try writeData(updatedRawData, to: storageFileURL)
            let nextVersion = currentVersion + 1
            try writeDataVersion(nextVersion, to: versionFileURL)

            cachedStorage = storage
            lastLoadedModificationDate = modificationDate(for: storageFileURL)
            lastLoadedVersion = nextVersion
        }
    }
}
