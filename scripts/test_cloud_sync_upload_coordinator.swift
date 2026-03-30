import Foundation

@main
struct CloudSyncUploadCoordinatorTests {
    static func main() {
        var coordinator = CloudSyncUploadCoordinator()

        expectEqual(
            coordinator.actionForUploadRequest(trigger: "LocalSave", isSyncing: false),
            .startNow("LocalSave"),
            "idle uploads should start immediately"
        )

        expectEqual(
            coordinator.actionForUploadRequest(trigger: "AppActive", isSyncing: true),
            .deferUntilIdle,
            "uploads requested during an active sync should be deferred"
        )
        expectEqual(
            coordinator.actionForUploadRequest(trigger: "LocalSave", isSyncing: true),
            .deferUntilIdle,
            "new upload requests during a sync should keep deferring"
        )

        expectEqual(
            coordinator.takeDeferredTrigger(),
            "LocalSave",
            "the latest deferred upload trigger should win"
        )
        expectEqual(
            coordinator.takeDeferredTrigger(),
            nil,
            "taking the deferred trigger should clear it"
        )

        print("PASS")
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fputs("FAIL: \(message)\nactual: \(actual)\nexpected: \(expected)\n", stderr)
            exit(1)
        }
    }
}
