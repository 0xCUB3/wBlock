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
        // Writes that share blocks with a sibling still hold exactly the given bytes.
        let base = root.appendingPathComponent("rules_ads_ios.shared.json")
        let prefix = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try prefix.write(to: base)
        for data in [prefix, prefix + Data("tail".utf8), prefix.prefix(200_000), prefix.prefix(100_000) + Data(count: 50),
                     Data("small".utf8), Data([1]) + prefix] {
            try FilterArtifactStorage.write(data, to: rules, sharingBlocksWith: base)
            expect(try Data(contentsOf: rules) == data && excluded(rules))
            try FilterArtifactStorage.write(data, to: rules, sharingBlocksWith: rules)
            expect(try Data(contentsOf: rules) == data)
        }
        try FilterArtifactStorage.write(prefix, to: rules, sharingBlocksWith: root.appendingPathComponent("missing"))
        expect(try Data(contentsOf: rules) == prefix && Data(contentsOf: base) == prefix)
        let legacy = try make("rules_ads_ios.base.json")
        let custom = try make("custom-\(UUID().uuidString).txt", old: true)
        let settings = try make("ProtobufData", folder: true)
        let unknown = try make("temp_notes.txt", old: true)
        let scratch = root.appendingPathComponent("Library/Caches/FilterCompilation")
        try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
        func inputName() -> String { "temp_skula.wBlock.wBlock-Ads-iOS_\(UUID().uuidString).txt" }
        let input = try make(inputName())
        let scratchInput = try make(inputName(), in: scratch)
        let outside = try make("outside", folder: true)
        let outsideInput = try make(inputName(), in: outside)
        let symlink = root.appendingPathComponent(inputName())
        try manager.createSymbolicLink(at: symlink, withDestinationURL: outsideInput)
        FilterArtifactStorage.maintain(container: root, generatedFilenames: [legacy.lastPathComponent, "../outside"])
        expect(try excluded(legacy))
        for url in [root, custom, settings, unknown] {
            expect(try !excluded(url), "authoritative and unknown data must remain backup eligible")
        }
        for url in [input, scratch, scratchInput, symlink] { expect(!manager.fileExists(atPath: url.path), url.path) }
        for url in [custom, unknown, outsideInput] { expect(manager.fileExists(atPath: url.path)) }
        FilterArtifactStorage.maintain(container: root, generatedFilenames: [])
        print("PASS filter artifact backup flags, atomic rewrites, migration, legacy cleanup, source preservation, symlink safety, block sharing")
    }
}
