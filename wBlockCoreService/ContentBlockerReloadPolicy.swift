import Foundation

public enum ContentBlockerReloadPolicy {
    public static let recoveryThreshold = 3
    public static let recoveryTimeout: TimeInterval = 45
    private static let prefix = "wBlock.reloadFailureStreak."

    public static func failureStreak(identifier: String, groupIdentifier: String) -> Int {
        max(0, UserDefaults(suiteName: groupIdentifier)?.integer(forKey: prefix + identifier) ?? 0)
    }

    public static func needsRecovery(identifier: String, groupIdentifier: String) -> Bool {
        failureStreak(identifier: identifier, groupIdentifier: groupIdentifier) >= recoveryThreshold
    }

    public static func record(
        identifier: String, groupIdentifier: String, success: Bool,
        attempts: Int, disabledInSafari: Bool = false
    ) {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else { return }
        if success {
            defaults.removeObject(forKey: prefix + identifier)
        } else if attempts > 0 && !disabledInSafari {
            defaults.set(min(100, failureStreak(identifier: identifier, groupIdentifier: groupIdentifier) + 1),
                         forKey: prefix + identifier)
        }
    }

    public static func orderedTargets(
        _ targets: [ContentBlockerTargetInfo], ruleCounts: [String: Int],
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> [ContentBlockerTargetInfo] {
        let recovering = Set(targets.filter {
            needsRecovery(identifier: $0.bundleIdentifier, groupIdentifier: groupIdentifier)
        }.map(\.bundleIdentifier))
        return targets.sorted {
            let left = recovering.contains($0.bundleIdentifier)
            let right = recovering.contains($1.bundleIdentifier)
            if left != right { return left }
            let leftCount = ruleCounts[$0.bundleIdentifier] ?? 0
            let rightCount = ruleCounts[$1.bundleIdentifier] ?? 0
            if leftCount != rightCount { return leftCount > rightCount }
            return $0.slot < $1.slot
        }
    }
}
