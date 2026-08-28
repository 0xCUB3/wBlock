import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct CloudSyncCustomFilterTests {
    static func main() {
        let mergedWithLocalReAdd = CloudSyncCustomFilterReconciler.deletedURLsToMergeDuringUploadReconciliation(
            remoteDeletedURLs: ["https://example.com/filter.txt"],
            localCustomURLs: ["https://example.com/filter.txt"]
        )
        expect(
            mergedWithLocalReAdd.isEmpty,
            "a locally re-added custom filter should not be re-deleted by a stale remote tombstone"
        )

        let mergedWithoutLocalCopy = CloudSyncCustomFilterReconciler.deletedURLsToMergeDuringUploadReconciliation(
            remoteDeletedURLs: ["https://example.com/filter.txt"],
            localCustomURLs: []
        )
        expect(
            mergedWithoutLocalCopy == ["https://example.com/filter.txt"],
            "remote tombstones should still merge when the custom filter is absent locally"
        )

        let mergedDuringRemoteApplyWithLiveRemote = CloudSyncCustomFilterReconciler.deletedURLsToMergeDuringRemoteApply(
            remoteDeletedURLs: ["https://example.com/filter.txt"],
            remoteCustomURLs: ["https://example.com/filter.txt"],
            localCustomURLs: []
        )
        expect(
            mergedDuringRemoteApplyWithLiveRemote.isEmpty,
            "a remote custom filter should win over a stale remote tombstone during remote apply"
        )

        let mergedDuringRemoteApplyWithLiveLocal = CloudSyncCustomFilterReconciler.deletedURLsToMergeDuringRemoteApply(
            remoteDeletedURLs: ["https://example.com/filter.txt"],
            remoteCustomURLs: [],
            localCustomURLs: ["https://example.com/filter.txt"]
        )
        expect(
            mergedDuringRemoteApplyWithLiveLocal.isEmpty,
            "a local custom filter should not be removed by a stale remote tombstone during remote apply"
        )

        let deletedToClear = CloudSyncCustomFilterReconciler.deletedURLsToClearDuringReconciliation(
            existingDeletedURLMarkers: ["https://example.com/filter.txt": 100],
            remoteCustomURLs: ["https://example.com/filter.txt"],
            localCustomURLs: [],
            remoteUpdatedAt: 200
        )
        expect(
            deletedToClear == ["https://example.com/filter.txt"],
            "live remote custom filters should clear stale local delete markers"
        )

        let deletedToKeep = CloudSyncCustomFilterReconciler.deletedURLsToClearDuringReconciliation(
            existingDeletedURLMarkers: ["https://example.com/filter.txt": 300],
            remoteCustomURLs: ["https://example.com/filter.txt"],
            localCustomURLs: [],
            remoteUpdatedAt: 200
        )
        expect(
            deletedToKeep.isEmpty,
            "a fresh local delete marker should survive an older remote payload during sync"
        )

        let deletedToClearWithLiveLocal = CloudSyncCustomFilterReconciler.deletedURLsToClearDuringReconciliation(
            existingDeletedURLMarkers: ["https://example.com/filter.txt": 300],
            remoteCustomURLs: [],
            localCustomURLs: ["https://example.com/filter.txt"],
            remoteUpdatedAt: 200
        )
        expect(
            deletedToClearWithLiveLocal == ["https://example.com/filter.txt"],
            "a live local custom filter should clear a stale delete marker even when the remote payload is older"
        )

        let deletedToKeepWithoutFreshRemoteTimestamp = CloudSyncCustomFilterReconciler
            .deletedURLsToClearDuringReconciliation(
                existingDeletedURLMarkers: ["https://example.com/filter.txt": 100],
                remoteCustomURLs: ["https://example.com/filter.txt"],
                localCustomURLs: [],
                remoteUpdatedAt: 0
            )
        expect(
            deletedToKeepWithoutFreshRemoteTimestamp.isEmpty,
            "a remote custom filter with no usable payload timestamp should not clear a delete marker"
        )

        let addedDuringSync = CloudSyncCustomFilterReconciler.tombstonedURLsToDelete(
            tombstonedURLs: ["https://example.com/filter.txt"],
            snapshotCustomURLs: [],
            liveCustomURLs: ["https://example.com/filter.txt"]
        )
        expect(
            addedDuringSync.isEmpty,
            "a custom filter added after the sync snapshot must not be deleted by a stale tombstone"
        )

        let presentAtSnapshot = CloudSyncCustomFilterReconciler.tombstonedURLsToDelete(
            tombstonedURLs: ["https://example.com/filter.txt"],
            snapshotCustomURLs: ["https://example.com/filter.txt"],
            liveCustomURLs: ["https://example.com/filter.txt"]
        )
        expect(
            presentAtSnapshot == ["https://example.com/filter.txt"],
            "a tombstone still removes a custom filter that was already present at snapshot time"
        )

        print("PASS")
    }
}
