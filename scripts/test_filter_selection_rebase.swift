import Foundation

@main
struct FilterSelectionRebaseTests {
    static func main() {
        let id = UUID()
        let otherID = UUID()
        let snapshot = [
            FilterList(id: id, name: "Updated", url: URL(string: "https://example.com")!, category: .ads, isSelected: true),
            FilterList(id: otherID, name: "New", url: URL(string: "https://example.com/new")!, category: .privacy, isSelected: true)
        ]
        let persisted = [
            FilterList(
                id: id,
                name: "User Renamed",
                url: URL(string: "https://example.com")!,
                category: .security,
                isSelected: false,
                description: "User Description",
                hasUserProvidedName: true,
                hasUserProvidedDescription: true,
                excludedSites: ["nytimes.com"]
            )
        ]
        let rebased = FilterSelectionRebaser.rebaseSelection(snapshot: snapshot, latestPersisted: persisted)

        guard rebased.first?.isSelected == false else {
            fputs("FAIL: latest persisted selection must win\n", stderr)
            exit(1)
        }
        guard rebased.first?.category == .security, rebased.last?.category == .privacy else {
            fatalError("Category edits must survive updates without changing newly added lists")
        }
        guard rebased.first?.excludedSites == ["nytimes.com"] else {
            fputs("FAIL: latest persisted per-list exclusions must win\n", stderr)
            exit(1)
        }
        guard rebased.first?.name == "User Renamed",
              rebased.first?.description == "User Description",
              rebased.first?.hasUserProvidedName == true,
              rebased.first?.hasUserProvidedDescription == true else {
            fputs("FAIL: user metadata edits made during a suspended download must win\n", stderr)
            exit(1)
        }
        guard rebased.last?.isSelected == true else {
            fputs("FAIL: filters absent from persisted state must retain snapshot selection\n", stderr)
            exit(1)
        }
        print("PASS")
    }
}
