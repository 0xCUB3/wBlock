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
        if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--claim-child" {
            runClaimChild(
                suite: CommandLine.arguments[2],
                lockDirectory: URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true),
                resultURL: URL(fileURLWithPath: CommandLine.arguments[4])
            )
            return
        }

        let suite = "test.wblock.popup-status.\(UUID().uuidString)"
        let lockDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-popup-status-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("missing test defaults") }
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: lockDirectory)
        }

        guard let claim = FilterUpdatePopupStatus.beginIfIdle(
            groupIdentifier: suite,
            lockDirectory: lockDirectory
        ) else { fatalError("update should begin") }
        expect(FilterUpdatePopupStatus.consumeSnapshot(groupIdentifier: suite, lockDirectory: lockDirectory).state == .running,
               "reading a running update must not acknowledge it")
        expect(FilterUpdatePopupStatus.snapshot(groupIdentifier: suite, lockDirectory: lockDirectory).state == .running,
               "running state must remain available to polling")

        let completion = SharedAutoUpdateManager.AutoUpdateCompletion(
            result: .noFilterUpdates,
            checkedFilters: 12,
            updatedFilters: 0,
            updatedScripts: 0,
            failedScripts: 0
        )
        expect(!FilterUpdatePopupStatus.finish(
            .completed(completion),
            claim: .init(rawValue: "stale-owner"),
            groupIdentifier: suite,
            lockDirectory: lockDirectory
        ), "a stale owner must not finish another claim")
        expect(FilterUpdatePopupStatus.snapshot(groupIdentifier: suite, lockDirectory: lockDirectory).state == .running,
               "stale finish must not alter running state")
        expect(FilterUpdatePopupStatus.finish(
            .completed(completion),
            claim: claim,
            groupIdentifier: suite,
            lockDirectory: lockDirectory
        ), "claim owner should finish")

        let terminal = FilterUpdatePopupStatus.consumeSnapshot(groupIdentifier: suite, lockDirectory: lockDirectory)
        expect(terminal.state == .noChange, "the finishing popup must receive the terminal result")
        expect(terminal.checkedFilters == 12, "terminal result must retain its stats")

        let reopened = FilterUpdatePopupStatus.snapshot(groupIdentifier: suite, lockDirectory: lockDirectory)
        expect(reopened.state == .idle, "a reopened popup must not repeat an acknowledged result")
        expect(reopened.startedAt == nil && reopened.finishedAt == nil,
               "acknowledgement must clear stale timestamps")
        expect(reopened.checkedFilters == 0 && reopened.updatedFilters == 0,
               "acknowledgement must clear stale counts")

        testStaleRequestDoesNotAttachToNewClaim(lockDirectory: lockDirectory)
        testCrossProcessClaim(lockDirectory: lockDirectory)

        print("PASS")
    }

    private static func testStaleRequestDoesNotAttachToNewClaim(lockDirectory: URL) {
        let suite = "test.wblock.popup-status.stale-request.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("missing stale-request defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }

        let old = FilterUpdatePopupStatus.requestUpdate(
            groupIdentifier: suite,
            now: Date(timeIntervalSince1970: 1),
            lockDirectory: lockDirectory
        )
        expect(old != nil, "old app request should be created")

        let replacement = FilterUpdatePopupStatus.beginIfIdle(
            groupIdentifier: suite,
            now: Date(timeIntervalSince1970: 1_000),
            lockDirectory: lockDirectory
        )
        expect(replacement != nil, "stale running generation should permit a new claim")
        expect(FilterUpdatePopupStatus.consumeUpdateRequest(
            groupIdentifier: suite,
            lockDirectory: lockDirectory
        ) == nil, "new direct claim must clear the stale request bit")
    }

    private static func testCrossProcessClaim(lockDirectory: URL) {
        let suite = "test.wblock.popup-status.concurrent.\(UUID().uuidString)"
        let result1 = lockDirectory.appendingPathComponent("claim-1.txt")
        let result2 = lockDirectory.appendingPathComponent("claim-2.txt")
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let children = [result1, result2].map { resultURL -> Process in
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--claim-child", suite, lockDirectory.path, resultURL.path]
            try! process.run()
            return process
        }
        children.forEach { $0.waitUntilExit() }
        let results = [result1, result2].map { (try? String(contentsOf: $0, encoding: .utf8)) ?? "" }
        let winners = results.filter { $0.hasPrefix("won:") }
        expect(winners.count == 1, "exactly one process must win the shared claim")

        if let defaults = UserDefaults(suiteName: suite) {
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private static func runClaimChild(suite: String, lockDirectory: URL, resultURL: URL) {
        let token = FilterUpdatePopupStatus.beginIfIdle(
            groupIdentifier: suite,
            lockDirectory: lockDirectory
        )
        let result = token.map { "won:\($0.rawValue)" } ?? "lost"
        try! result.write(to: resultURL, atomically: true, encoding: .utf8)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
