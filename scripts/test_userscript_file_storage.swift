import Foundation

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
        print("PASS: shared updates supersede private source and resources; legacy migration preserved")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }
}
