import Foundation

@main
struct StagedFilterDownloadsTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("staged-filter-downloads-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appendingPathComponent(StagedFilterDownloads.filename)
        let first = require(StagedFilterDownloads.save(filterIDs: ["first"], storeURL: storeURL),
                            "first marker should save")
        let second = require(StagedFilterDownloads.save(filterIDs: ["second"], storeURL: storeURL),
                             "second marker should save")
        expect(first.generation != second.generation, "each staging write must get a new generation")

        expect(!StagedFilterDownloads.clear(ifMatches: first, storeURL: storeURL),
               "an older consumer must not clear a newer staging generation")
        expect(StagedFilterDownloads.load(storeURL: storeURL) == second,
               "newer staging generation must survive stale compare-and-clear")
        expect(StagedFilterDownloads.clear(ifMatches: second, storeURL: storeURL),
               "the consumer that observed the current generation should clear it")
        expect(StagedFilterDownloads.load(storeURL: storeURL) == nil,
               "matching compare-and-clear should remove the marker")

        let legacy = StagedFilterDownloads.Marker(filterIDs: ["legacy"], stagedAt: 123, generation: nil)
        let legacyData = try JSONEncoder().encode(legacy)
        try legacyData.write(to: storeURL, options: .atomic)
        expect(StagedFilterDownloads.load(storeURL: storeURL) == legacy,
               "pre-generation markers must remain decodable")
        expect(StagedFilterDownloads.clear(ifMatches: legacy, storeURL: storeURL),
               "a consumer may clear the exact legacy marker it observed")

        print("PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    private static func require<T>(_ value: T?, _ message: String) -> T {
        guard let value else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
        return value
    }
}
