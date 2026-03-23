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

        print("PASS")
    }
}
