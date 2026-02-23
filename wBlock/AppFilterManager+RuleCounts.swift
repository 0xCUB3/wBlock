import Foundation
import wBlockCoreService

extension AppFilterManager {
    func loadSavedRuleCounts() {
        // Load last known rule count from protobuf data
        lastRuleCount = dataManager.lastRuleCount

        // Load extension-specific rule counts
        // Stored keys may be legacy category names or (new) bundle identifiers.
        for (categoryKey, count) in dataManager.ruleCountsByCategory {
            if ContentBlockerTargetManager.shared.targetInfo(forBundleIdentifier: categoryKey, platform: currentPlatform) != nil {
                ruleCountsByExtension[categoryKey] = Int(count)
                continue
            }

            if let category = FilterListCategory(rawValue: categoryKey),
               let legacyBundleID = legacyBundleIdentifier(for: category) {
                if ruleCountsByExtension[legacyBundleID] == nil {
                    ruleCountsByExtension[legacyBundleID] = Int(count)
                }
            }
        }

        // Load extensions approaching limit (legacy category names or bundle identifiers).
        for identifierOrCategory in dataManager.categoriesApproachingLimit {
            if ContentBlockerTargetManager.shared.targetInfo(forBundleIdentifier: identifierOrCategory, platform: currentPlatform) != nil {
                extensionsApproachingLimit.insert(identifierOrCategory)
                continue
            }
            if let category = FilterListCategory(rawValue: identifierOrCategory),
               let legacyBundleID = legacyBundleIdentifier(for: category) {
                extensionsApproachingLimit.insert(legacyBundleID)
            }
        }
    }

    func saveRuleCounts() {
        Task { @MainActor in
            let platformTargets = ContentBlockerTargetManager.shared.allTargets(forPlatform: currentPlatform)
            let countsByIdentifier = Dictionary(
                uniqueKeysWithValues: platformTargets.map { target in
                    (target.bundleIdentifier, ruleCountsByExtension[target.bundleIdentifier] ?? 0)
                }
            )
            let approaching = Set(platformTargets.map(\.bundleIdentifier)).intersection(extensionsApproachingLimit)

            await dataManager.updateRuleCounts(
                lastRuleCount: lastRuleCount,
                ruleCountsByIdentifier: countsByIdentifier,
                identifiersApproachingLimit: approaching
            )
        }
    }

    func legacyBundleIdentifier(for category: FilterListCategory) -> String? {
        let slot: Int?
        switch category {
        case .ads:
            slot = 1
        case .privacy:
            slot = 2
        case .security, .annoyances, .multipurpose:
            slot = 3
        case .foreign, .experimental:
            slot = 4
        case .custom:
            slot = 5
        default:
            slot = nil
        }

        guard let slot = slot else { return nil }
        return ContentBlockerTargetManager.shared
            .allTargets(forPlatform: currentPlatform)
            .first { $0.slot == slot }?
            .bundleIdentifier
    }
}
