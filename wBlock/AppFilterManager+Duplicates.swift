import Foundation
import wBlockCoreService

extension AppFilterManager {
    /// Pairs already answered on this device, so each one is asked about once.
    private static let answeredDuplicatePairsKey = "wBlock.answeredDuplicateListPairs"

    private var answeredDuplicatePairs: Set<String> {
        get {
            let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
            return Set(defaults.stringArray(forKey: Self.answeredDuplicatePairsKey) ?? [])
        }
        set {
            let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
            defaults.set(newValue.sorted(), forKey: Self.answeredDuplicatePairsKey)
        }
    }

    /// Asks about the first custom list that copies another downloaded list.
    func checkForDuplicateLists() async {
        guard duplicateListPair == nil, let containerURL = loader.getSharedContainerURL() else { return }
        let lists = filterLists, answered = answeredDuplicatePairs
        let pair = await Task.detached(priority: .utility) {
            FilterListDuplicates.pairs(in: lists, dismissed: answered) { list in
                guard let url = ContentBlockerIncrementalCache.existingLocalFileURL(for: list, containerURL: containerURL),
                      let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return FilterListDuplicates.rules(in: text)
            }.first
        }.value
        guard let pair, duplicateListPair == nil,
              filterLists.contains(where: { $0.id == pair.copy.id }) else { return }
        duplicateListPair = pair
    }

    /// Records the answer. Removing the copy turns the kept list on if the
    /// copy was protecting in its place.
    func resolveDuplicateLists(_ pair: FilterListDuplicates.Pair, removeCopy: Bool) {
        answeredDuplicatePairs.insert(pair.key)
        duplicateListPair = nil
        guard removeCopy, let copy = filterLists.first(where: { $0.id == pair.copy.id }) else { return }
        if copy.isSelected { setFilterListSelection(id: pair.original.id, selected: true) }
        removeCustomFilterList(copy)
    }
}
