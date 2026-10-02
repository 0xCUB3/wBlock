import Foundation

private final class FailingRemovalFileManager: FileManager, @unchecked Sendable {
    var blockedURL: URL?
    override func removeItem(at URL: URL) throws {
        if URL == blockedURL { throw CocoaError(.fileWriteNoPermission) }
        try super.removeItem(at: URL)
    }
}

@main
struct UserScriptFileStorageTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appendingPathComponent("shared")
        let app = root.appendingPathComponent("app")
        let extensionCache = root.appendingPathComponent("extension")
        for directory in [shared, app, extensionCache] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        func write(_ text: String, _ directory: URL, _ name: String = "script.user.js") throws {
            try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        func read(_ directories: [URL], _ name: String = "script.user.js") -> String? {
            UserScriptFileStorage.read(fileName: name, directories: directories) { String(data: $0, encoding: .utf8) }
        }
        try write("old", extensionCache)
        try write("new", app)
        try write("new", shared)
        expect(read([shared, extensionCache]) == "new", "extension must not execute its stale private copy")
        expect(read([shared, app]) == "new", "app and extension must agree")
        try write("next", shared)
        expect(read([shared, extensionCache]) == "next", "subsequent shared updates must be visible")
        expect(read([shared, app]) == "next", "shared update must also supersede app-private source")
        try write("legacy", extensionCache, "legacy.user.js")
        expect(read([shared, extensionCache], "legacy.user.js") == "legacy", "legacy fallback remains readable")
        expect(read([shared], "legacy.user.js") == "legacy", "legacy fallback migrates to shared storage")
        try write("authoritative", shared, "legacy.user.js")
        expect(read([shared, extensionCache], "legacy.user.js") == "authoritative", "migration must not replace shared updates")
        try write("{\"css\":\"new\"}", shared, "script.resources.json")
        try write("{\"css\":\"old\"}", extensionCache, "script.resources.json")
        let resources = UserScriptFileStorage.read(fileName: "script.resources.json", directories: [shared, extensionCache]) {
            try? JSONDecoder().decode([String: String].self, from: $0)
        }
        expect(resources?["css"] == "new", "resources must use the same shared-first ordering")
        expect(read([extensionCache]) == "old", "private-only storage still works without an app group")
        expect(read([shared, extensionCache], "missing") == nil, "missing source stays missing")
        expect(read([]) == nil, "no available directories is safe")
        let artifacts = ["script.user.js", "script.resources.json", "script.user.css.compiled.v1.json"]
        for directory in [shared, app] {
            for name in artifacts { try write("cache", directory, name) }
            try write("local source", directory, "local.user.js")
        }
        let manager = FailingRemovalFileManager()
        let blocked = shared.appendingPathComponent(artifacts[1])
        manager.blockedURL = blocked
        do {
            try UserScriptFileStorage.remove(fileNames: artifacts, directories: [shared, app], fileManager: manager)
            fatalError("A failed sidecar removal must not be reported as successful eviction")
        } catch let error as CocoaError {
            expect(error.code == .fileWriteNoPermission, "report the deletion failure")
        }
        expect(FileManager.default.fileExists(atPath: blocked.path), "the blocked sidecar remains retryable")
        expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent(artifacts[2]).path),
               "continue removing other copies after a failure")
        manager.blockedURL = nil
        try UserScriptFileStorage.remove(fileNames: artifacts, directories: [shared, app], fileManager: manager)
        try UserScriptFileStorage.remove(fileNames: artifacts, directories: [shared, app], fileManager: manager)
        for directory in [shared, app] {
            for name in artifacts {
                expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path),
                       "all downloaded source and sidecar copies must be removed")
            }
            expect(read([directory], "local.user.js") == "local source", "unrelated local imports survive eviction")
        }
        print("PASS: shared-first reads, migration, complete eviction, failure reporting and safe retry")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }
}
