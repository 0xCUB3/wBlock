import Foundation
import wBlockCoreService

@main struct FilterListSetupTests {
    static func main() throws {
        let url = URL(string: "https://example.com/list.txt")!
        let catalog = FilterList(name: "Catalog title", url: url, category: .ads, description: "Catalog description")
        var builtin = catalog
        builtin.category = .security
        builtin.name = "Old catalog title"
        let custom = FilterList(name: "My title", url: url, category: .privacy, isCustom: true,
                                isSelected: true, description: "My description", hasUserProvidedName: true)
        let inline = FilterList(name: "Local rules", url: URL(string: "wblock://userlist/\(UUID())")!,
                                category: .annoyances, isCustom: true)
        let duplicate = FilterList(name: "Duplicate catalog", url: url, category: .ads, isSelected: true)
        for input in [[builtin, custom, inline, duplicate], [custom, builtin, inline, duplicate]] {
            let decoded = try JSONDecoder().decode([FilterList].self, from: JSONEncoder().encode(input))
            let hydrated = FilterListSetup.hydrate(decoded, defaults: [catalog])
            precondition(hydrated.count == 2, "custom and duplicate copies of a catalog URL fold into one entry")
            precondition(hydrated.first { $0.id == inline.id } == inline, "local user lists retain their category")
            let loaded = hydrated.first { $0.url == url }!
            precondition(!loaded.isCustom && loaded.isSelected && loaded.name == catalog.name && loaded.description == catalog.description)
            precondition(FilterListSetup.hydrate(hydrated, defaults: [catalog]) == hydrated, "setup is idempotent")
        }
        let solo = FilterListSetup.hydrate([builtin], defaults: [catalog])[0]
        precondition(solo.category == catalog.category, "a built-in list follows its catalog category")
        let folded = FilterListSetup.hydrate([custom], defaults: [catalog])[0]
        precondition(folded.id == custom.id && !folded.isCustom && folded.isSelected && folded.category == catalog.category,
                     "a custom copy keeps its ID and selection and takes the catalog category when it folds in")
        precondition(folded.name == catalog.name && folded.description == catalog.description && !folded.hasUserProvidedName)
        let first = FilterList(name: "First", url: URL(string: "https://example.com/first")!, category: .annoyances)
        let restored = FilterList(name: "Restored", url: URL(string: "https://example.com/restored")!, category: .annoyances)
        let last = FilterList(name: "Last", url: URL(string: "https://example.com/last")!, category: .annoyances)
        let defaults = [first, restored, last]
        let upgraded = FilterListSetup.hydrate([first, last, restored, custom, inline], defaults: defaults)
        precondition(upgraded.map(\.id) == [first.id, restored.id, last.id, custom.id, inline.id],
                     "restored defaults follow catalog order rather than their appended storage position")
        precondition(FilterListSetup.hydrate(upgraded, defaults: defaults) == upgraded)
        let locked = FilterList(name: "🔒 Privacy Essentials", url: URL(string: "https://example.com/pe.txt")!, category: .custom, isCustom: true)
        let named = FilterList(name: "🔒 Mine", url: URL(string: "https://example.com/mine.txt")!, category: .custom, isCustom: true, hasUserProvidedName: true)
        let cleaned = FilterListSetup.hydrate([locked, named], defaults: defaults)
        precondition(cleaned.map(\.name) == ["Privacy Essentials", "🔒 Mine"], "header names drop emoji, user names stay: \(cleaned.map(\.name))")
        precondition(FilterListContentProcessing.parseMetadata(from: "! Title: 🔒 Privacy Essentials 2\n").title == "Privacy Essentials 2")
        print("PASS setup category, identity, and catalog order round trips")
    }
}
