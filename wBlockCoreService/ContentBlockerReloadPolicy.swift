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

    public typealias TargetReload = (
        target: ContentBlockerTargetInfo, reload: ContentBlockerService.ReloadAttemptResult
    )

    /// Reloads `targets` in one pass and returns after every target has finished.
    /// The pass is always timed: a target Safari already has still costs a state
    /// query and a hash of its rules, so an all-skipped pass is not free.
    public static func reloadPass(
        _ targets: [ContentBlockerTargetInfo],
        groupIdentifier: String,
        maxConcurrent: Int = 1,
        reload: (@Sendable (ContentBlockerTargetInfo) async -> ContentBlockerService.ReloadAttemptResult)? = nil,
        onResult: (TargetReload) async -> Void = { _ in }
    ) async -> (results: [TargetReload], durationMs: Int) {
        let started = Date()
        let reload = reload ?? { target in
            await ContentBlockerService.reloadIfNeeded(
                identifier: target.bundleIdentifier,
                targetRulesFilename: target.rulesFilename,
                groupIdentifier: groupIdentifier
            )
        }
        var results: [TargetReload] = []
        await boundedConcurrentForEach(targets, maxConcurrent: maxConcurrent, operation: { target in
            (target: target, reload: await reload(target))
        }, onResult: { item in
            results.append(item)
            await onResult(item)
        })
        return (results, Int(Date().timeIntervalSince(started) * 1000))
    }

    public static func orderedTargets(
        _ targets: [ContentBlockerTargetInfo], ruleCounts: [String: Int],
        groupIdentifier: String = GroupIdentifier.shared.value
    ) -> [ContentBlockerTargetInfo] {
        let recovering = Set(targets.filter {
            needsRecovery(identifier: $0.bundleIdentifier, groupIdentifier: groupIdentifier)
        }.map(\.bundleIdentifier))
        let ordered = targets.sorted {
            let left = recovering.contains($0.bundleIdentifier)
            let right = recovering.contains($1.bundleIdentifier)
            if left != right { return left }
            let leftCount = ruleCounts[$0.bundleIdentifier] ?? 0
            let rightCount = ruleCounts[$1.bundleIdentifier] ?? 0
            if leftCount != rightCount { return leftCount > rightCount }
            return $0.slot < $1.slot
        }
        let fields = ["order": ordered.map { $0.bundleIdentifier }.joined(separator: ","),
                      "ruleCounts": ordered.map { String(ruleCounts[$0.bundleIdentifier] ?? 0) }.joined(separator: ","),
                      "recoveryTargets": recovering.sorted().joined(separator: ",")]
        Task { await SharedAutoUpdateManager.shared.recordOperation("reload-order", fields: fields) }
        return ordered
    }
}
