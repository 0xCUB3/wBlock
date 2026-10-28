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
            precondition(hydrated.count == 3, "only built-in duplicate URLs collapse")
            precondition(hydrated.first { $0.id == custom.id } == custom, "custom category, identity, and metadata survive setup")
            precondition(hydrated.first { $0.id == inline.id } == inline, "local user lists retain their category")
            let loaded = hydrated.first { $0.id == builtin.id }!
            precondition(loaded.category == .security, "catalog hydration must preserve the moved built-in category")
            precondition(loaded.name == catalog.name && loaded.description == catalog.description && loaded.isSelected)
            precondition(FilterListSetup.hydrate(hydrated, defaults: [catalog]) == hydrated, "setup is idempotent")
        }
        let first = FilterList(name: "First", url: URL(string: "https://example.com/first")!, category: .annoyances)
        let restored = FilterList(name: "Restored", url: URL(string: "https://example.com/restored")!, category: .annoyances)
        let last = FilterList(name: "Last", url: URL(string: "https://example.com/last")!, category: .annoyances)
        let defaults = [first, restored, last]
        let upgraded = FilterListSetup.hydrate([first, last, restored, custom, inline], defaults: defaults)
        precondition(upgraded.map(\.id) == [first.id, restored.id, last.id, custom.id, inline.id],
                     "restored defaults follow catalog order rather than their appended storage position")
        precondition(FilterListSetup.hydrate(upgraded, defaults: defaults) == upgraded)
        print("PASS setup category, identity, and catalog order round trips")
    }
}
