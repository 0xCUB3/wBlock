import Foundation
import wBlockCoreService

@main
struct FilterListRemoteMetadataPolicyTests {
    static func main() throws {
        let url = URL(string: "https://example.com/filter.txt")!
        let automatic = FilterList(
            name: "filter",
            url: url,
            category: .custom,
            isCustom: true,
            description: "User-added filter list.",
            hasUserProvidedName: false,
            hasUserProvidedDescription: false
        )
        let hydrated = FilterListRemoteMetadataPolicy.applying(
            title: "Remote Title",
            description: "Remote Description",
            version: "2025.1",
            to: automatic
        )
        expectEqual(hydrated.name, "Remote Title", "remote title should fill automatic custom URL names")
        expectEqual(hydrated.description, "Remote Description", "remote description should fill automatic descriptions")
        expectEqual(hydrated.version, "2025.1", "remote version should update")

        let manual = FilterList(
            name: "My List",
            url: url,
            category: .custom,
            isCustom: true,
            description: "My Description",
            hasUserProvidedName: true,
            hasUserProvidedDescription: true
        )
        let preserved = FilterListRemoteMetadataPolicy.applying(
            title: "Remote Title",
            description: "Remote Description",
            version: nil,
            to: manual
        )
        expectEqual(preserved.name, "My List", "manual name should survive remote metadata")
        expectEqual(preserved.description, "My Description", "manual description should survive remote metadata")
        expectEqual(preserved.version, "Unknown", "missing remote version should remain the existing updater behavior")

        expect(ImportMetadataReview.userProvided(nil, automatic: "Remote Description") == nil,
               "untouched metadata should remain automatic")
        expect(ImportMetadataReview.userProvided(" Remote Description ", automatic: "Remote Description") == nil,
               "unchanged prefilled metadata should remain automatic")
        let clearedDescription = ImportMetadataReview.userProvided("", automatic: "Remote Description")
        expectEqual(clearedDescription, "", "a cleared prefill must remain an explicit empty override")
        let cleared = FilterList(
            name: "My List", url: url, category: .custom, isCustom: true,
            description: clearedDescription ?? "Remote Description",
            hasUserProvidedDescription: clearedDescription != nil
        )
        let restoredClear = try JSONDecoder().decode(FilterList.self, from: JSONEncoder().encode(cleared))
        let refreshedClear = FilterListRemoteMetadataPolicy.applying(
            title: nil, description: "New Remote Description", version: nil, to: restoredClear
        )
        expectEqual(refreshedClear.description, "", "refresh must not restore an intentionally cleared description")
        expect(refreshedClear.hasUserProvidedDescription, "persistence must keep the explicit-empty flag")

        let builtIn = FilterList(name: "Built-in", url: url, category: .ads, description: "Catalog Description")
        let builtInHydrated = FilterListRemoteMetadataPolicy.applying(
            title: "Remote Title", description: "Remote Description", version: "1", to: builtIn
        )
        expectEqual(builtInHydrated.description, "Catalog Description", "built-in lists keep the localized catalog description")

        let encoded = try JSONEncoder().encode(manual)
        let decoded = try JSONDecoder().decode(FilterList.self, from: encoded)
        expect(decoded.hasUserProvidedName, "Codable should persist manual name flag")
        expect(decoded.hasUserProvidedDescription, "Codable should persist manual description flag")

        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Legacy",
          "url": "https://example.com/legacy.txt",
          "category": "Custom",
          "isCustom": true,
          "isSelected": true,
          "description": "Legacy description"
        }
        """.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(FilterList.self, from: legacyJSON)
        expect(!legacy.hasUserProvidedDescription, "missing Codable description flag should default false for compatibility")

        print("PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fatalError("\(message). got \(actual), expected \(expected)")
        }
    }
}
