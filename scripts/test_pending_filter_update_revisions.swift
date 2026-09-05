import Foundation

@main
struct PendingFilterUpdateRevisionTests {
    static func main() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pending-filter-update-revisions-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = directory.appendingPathComponent(PendingFilterUpdateRevisions.filename)
        defer { try? FileManager.default.removeItem(at: directory) }

        let failedStoreDirectory = directory.appendingPathComponent("not-a-file")
        try? FileManager.default.createDirectory(
            at: failedStoreDirectory,
            withIntermediateDirectories: true
        )
        let failedRevision = PendingFilterUpdateRevisions.markDownloaded(
            filterID: UUID().uuidString,
            token: "unpersisted-token",
            storeURL: failedStoreDirectory
        )
        expect(failedRevision == nil, "download marking must fail when the pending revision cannot be persisted")
        expect(PendingFilterUpdateRevisions.load(storeURL: failedStoreDirectory).isEmpty,
               "failed persistence must not claim a pending revision exists")

        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        let deletedID = UUID().uuidString

        let firstRevision = PendingFilterUpdateRevisions.markDownloaded(
            filterID: firstID,
            etag: "etag-1",
            lastModified: "lm-1",
            version: "1",
            token: "token-1",
            now: 100,
            storeURL: storeURL
        )
        expect(firstRevision?.token == "token-1", "download marking should expose the stored token")
        expect(PendingFilterUpdateRevisions.contains(filterID: firstID, storeURL: storeURL),
               "failed or cancelled apply must leave a downloaded revision pending")

        let restartedStore = PendingFilterUpdateRevisions.load(storeURL: storeURL)
        expect(restartedStore[firstID]?.etag == "etag-1", "pending revisions must survive app reinstantiation")

        expect(
            PendingFilterUpdateRevisions.pendingFilterIDs(
                selectedFilterIDs: [firstID, secondID],
                storeURL: storeURL
            ) == [firstID],
            "manual checks should merge only pending selected filters"
        )
        expect(
            PendingFilterUpdateRevisions.pendingFilterIDs(
                selectedFilterIDs: [secondID],
                storeURL: storeURL
            ).isEmpty,
            "deselected filters should not reappear in manual check results"
        )

        let cancelledReview = PendingFilterUpdateRevisions.snapshot(filterIDs: [firstID], storeURL: storeURL)
        expect(!cancelledReview.isEmpty, "review cancellation should not consume the pending token")
        expect(PendingFilterUpdateRevisions.contains(filterID: firstID, storeURL: storeURL),
               "pending review should still be available on the next check")

        PendingFilterUpdateRevisions.markDownloaded(
            filterID: secondID,
            version: "2",
            token: "token-2",
            now: 200,
            storeURL: storeURL
        )
        let successfulApply = PendingFilterUpdateRevisions.snapshot(
            filterIDs: [firstID, secondID],
            storeURL: storeURL
        )
        PendingFilterUpdateRevisions.acknowledge(successfulApply, storeURL: storeURL)
        expect(PendingFilterUpdateRevisions.load(storeURL: storeURL).isEmpty,
               "successful apply should clear only acknowledged revisions")

        PendingFilterUpdateRevisions.markDownloaded(
            filterID: firstID,
            version: "old",
            token: "old-token",
            now: 300,
            storeURL: storeURL
        )
        let applySnapshot = PendingFilterUpdateRevisions.snapshot(filterIDs: [firstID], storeURL: storeURL)
        PendingFilterUpdateRevisions.markDownloaded(
            filterID: firstID,
            version: "new",
            token: "new-token",
            now: 400,
            storeURL: storeURL
        )
        PendingFilterUpdateRevisions.acknowledge(applySnapshot, storeURL: storeURL)
        expect(PendingFilterUpdateRevisions.load(storeURL: storeURL)[firstID]?.token == "new-token",
               "acknowledging an older apply snapshot must preserve a newer downloaded revision")

        PendingFilterUpdateRevisions.markDownloaded(
            filterID: deletedID,
            token: "deleted-token",
            now: 500,
            storeURL: storeURL
        )
        PendingFilterUpdateRevisions.remove(filterIDs: [deletedID], storeURL: storeURL)
        expect(!PendingFilterUpdateRevisions.contains(filterID: deletedID, storeURL: storeURL),
               "deleted or successfully deselected lists should drop obsolete pending revisions")

        let beforeFailedPublish = PendingFilterUpdateRevisions.load(storeURL: storeURL)
        let failedPublish = PendingFilterUpdateRevisions.markDownloaded(
            filterID: firstID,
            token: "failed-publication",
            storeURL: storeURL,
            publish: { throw CocoaError(.fileWriteNoPermission) }
        )
        expect(failedPublish == nil, "source publication failures must fail the download")
        expect(PendingFilterUpdateRevisions.load(storeURL: storeURL) == beforeFailedPublish,
               "failed publication must preserve an older pending revision")

        let sourceURL = directory.appendingPathComponent("source.txt")
        let snapshotFinished = DispatchSemaphore(value: 0)
        let published = PendingFilterUpdateRevisions.markDownloaded(
            filterID: firstID,
            token: "published-token",
            storeURL: storeURL,
            publish: {
                DispatchQueue.global().async {
                    let snapshot = PendingFilterUpdateRevisions.snapshot(filterIDs: [firstID], storeURL: storeURL)
                    expect(snapshot.tokensByFilterID[firstID] == "published-token", "snapshot should see the published token")
                    expect((try? String(contentsOf: sourceURL, encoding: .utf8)) == "new source",
                           "snapshot must not observe a new token paired with an old source")
                    snapshotFinished.signal()
                }
                expect(snapshotFinished.wait(timeout: .now() + 0.05) == .timedOut,
                       "snapshot must wait for source publication")
                try "new source".write(to: sourceURL, atomically: true, encoding: .utf8)
            }
        )
        expect(published != nil, "transactional source publication should succeed")
        expect(snapshotFinished.wait(timeout: .now() + 2) == .success, "snapshot should finish after publication")

        print("PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
