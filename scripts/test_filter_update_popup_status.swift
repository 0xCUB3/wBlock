import Foundation

public final class GroupIdentifier {
    public static let shared = GroupIdentifier()
    public let value = "test.wblock.popup-status.default"
}

public enum SharedAutoUpdateManager {
    public enum AutoUpdateCompletionResult: Sendable, Equatable {
        case appliedUpdates
        case stagedUpdates
        case noFilterUpdates
        case noSelectedFilters
    }

    public struct AutoUpdateCompletion: Sendable, Equatable {
        public let result: AutoUpdateCompletionResult
        public let checkedFilters: Int
        public let updatedFilters: Int
        public let updatedScripts: Int
        public let failedScripts: Int
    }

    public enum AutoUpdateRunOutcome: Sendable, Equatable {
        case completed(AutoUpdateCompletion)
        case skipped(reason: String)
        case cancelled
        case deferred(phase: String)
        case failed(message: String)
    }
}

@main
struct FilterUpdatePopupStatusTests {
    static func main() {
        let suite = "test.wblock.popup-status.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("missing test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }

        expect(FilterUpdatePopupStatus.beginIfIdle(groupIdentifier: suite), "update should begin")
        expect(FilterUpdatePopupStatus.consumeSnapshot(groupIdentifier: suite).state == .running,
               "reading a running update must not acknowledge it")
        expect(FilterUpdatePopupStatus.snapshot(groupIdentifier: suite).state == .running,
               "running state must remain available to polling")

        let completion = SharedAutoUpdateManager.AutoUpdateCompletion(
            result: .noFilterUpdates,
            checkedFilters: 12,
            updatedFilters: 0,
            updatedScripts: 0,
            failedScripts: 0
        )
        FilterUpdatePopupStatus.finish(.completed(completion), groupIdentifier: suite)

        let terminal = FilterUpdatePopupStatus.consumeSnapshot(groupIdentifier: suite)
        expect(terminal.state == .noChange, "the finishing popup must receive the terminal result")
        expect(terminal.checkedFilters == 12, "terminal result must retain its stats")

        let reopened = FilterUpdatePopupStatus.snapshot(groupIdentifier: suite)
        expect(reopened.state == .idle, "a reopened popup must not repeat an acknowledged result")
        expect(reopened.startedAt == nil && reopened.finishedAt == nil,
               "acknowledgement must clear stale timestamps")
        expect(reopened.checkedFilters == 0 && reopened.updatedFilters == 0,
               "acknowledgement must clear stale counts")

        print("PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
