import Foundation

@main
struct FilterArtifactStorageTests {
    private static func expect(_ condition: Bool, _ message: String = "", line: UInt = #line) {
        precondition(condition, "line \(line): \(message)")
    }

    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let now = Date()
        func make(_ name: String, in directory: URL? = nil, old: Bool = false, folder: Bool = false) throws -> URL {
            let url = (directory ?? root).appendingPathComponent(name)
            if folder { try manager.createDirectory(at: url, withIntermediateDirectories: true) }
            else { try Data("source".utf8).write(to: url) }
            if old { try manager.setAttributes([.modificationDate: now.addingTimeInterval(-8 * 86400)], ofItemAtPath: url.path) }
            return url
        }
        func excluded(_ url: URL) throws -> Bool {
            try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
        }
        let rules = try make("rules_ads_ios.json")
        expect(try !excluded(rules), "ordinary app-group files are backup eligible")
        try FilterArtifactStorage.write(Data("first".utf8), to: rules)
        expect(try excluded(rules))
        try FilterArtifactStorage.write(Data("replacement".utf8), to: rules)
        expect(try excluded(rules), "atomic rewrites must retain exclusion")
        expect(try String(contentsOf: rules, encoding: .utf8) == "replacement")
        let legacy = try make("rules_ads_ios.base.json")
        let custom = try make("custom-\(UUID().uuidString).txt", old: true)
        let settings = try make("ProtobufData", folder: true)
        let unknown = try make("temp_notes.txt", old: true)
        let engine = try make(".webext", folder: true)
        let scratch = try FilterArtifactStorage.scratchDirectory(in: root)
        expect(try excluded(scratch))
        func inputName() -> String { "temp_skula.wBlock.wBlock-Ads-iOS_\(UUID().uuidString).txt" }
        let staleInput = try make(inputName(), old: true)
        let recentInput = try make(inputName())
        let staleEngine = try make("engine-rebuild-\(UUID().uuidString)", in: engine, old: true, folder: true)
        let recentEngine = try make("engine-rebuild-\(UUID().uuidString)", in: scratch, folder: true)
        let staleScratch = try make(inputName(), in: scratch, old: true)
        let malformed = try make("engine-rebuild-not-a-uuid", in: engine, old: true, folder: true)
        let symlink = root.appendingPathComponent(inputName())
        try manager.createSymbolicLink(at: symlink, withDestinationURL: custom)
        FilterArtifactStorage.maintain(container: root, generatedFilenames: [legacy.lastPathComponent, "../outside"], now: now)
        for url in [legacy, engine, recentInput] { expect(try excluded(url)) }
        for url in [root, custom, settings, unknown] {
            expect(try !excluded(url), "authoritative and unknown data must remain backup eligible")
        }
        for url in [staleInput, staleEngine, staleScratch] { expect(!manager.fileExists(atPath: url.path), url.path) }
        for url in [recentInput, recentEngine, custom, unknown, malformed, symlink] { expect(manager.fileExists(atPath: url.path)) }
        // Maintenance is repeatable and must not follow a linked engine directory.
        try manager.removeItem(at: engine)
        let outside = try make("outside", folder: true)
        let outsideInput = try make(inputName(), in: outside, old: true)
        try manager.createSymbolicLink(at: engine, withDestinationURL: outside)
        FilterArtifactStorage.maintain(container: root, generatedFilenames: [], now: now)
        expect(manager.fileExists(atPath: outsideInput.path))
        expect(try !excluded(outsideInput))
        try manager.removeItem(at: scratch)
        try manager.createSymbolicLink(at: scratch, withDestinationURL: outside)
        do {
            _ = try FilterArtifactStorage.scratchDirectory(in: root)
            fatalError("scratch writers must not follow symlinks")
        } catch is CocoaError {}
        print("PASS filter artifact backup flags, atomic rewrites, migration, stale cleanup, source preservation, symlink safety")
    }
}
