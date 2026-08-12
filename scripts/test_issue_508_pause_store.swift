import Foundation

// Run from the repository root:
// swiftc wBlockCoreService/GroupIdentifier.swift wBlockCoreService/BlockingPauseStore.swift scripts/test_issue_508_pause_store.swift -o /tmp/test_issue_508_pause_store && /tmp/test_issue_508_pause_store

@main
struct Issue508PauseStoreTest {
    static func main() {
        let suiteName = "issue-508-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("could not create random UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: BlockingPauseStore.key)
        let migrated = BlockingPauseStore.pausedComponents(groupIdentifier: suiteName)
        require(migrated == .all, "legacy true must migrate to all components")
        require(
            defaults.integer(forKey: BlockingPauseStore.componentsKey) == BlockingPauseComponents.all.rawValue,
            "migration must persist the all-components mask"
        )

        let partial: BlockingPauseComponents = [.filters, .userScripts]
        BlockingPauseStore.setPausedComponents(partial, groupIdentifier: suiteName)
        let persistedPartial = BlockingPauseStore.pausedComponents(groupIdentifier: suiteName)
        require(persistedPartial == partial, "filters and userscripts must persist independently")
        require(!persistedPartial.contains(.elementZapper), "partial pause must not pause the zapper")
        require(defaults.bool(forKey: BlockingPauseStore.key), "legacy pause bool must remain true for partial pause")

        BlockingPauseStore.setPaused(false, groupIdentifier: suiteName)
        require(BlockingPauseStore.pausedComponents(groupIdentifier: suiteName).isEmpty, "resume must clear the component mask")
        require(!defaults.bool(forKey: BlockingPauseStore.key), "resume must clear the legacy pause bool")

        print("PASS: issue 508 executable pause-store persistence and migration")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
