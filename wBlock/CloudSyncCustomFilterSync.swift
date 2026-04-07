import Foundation

enum CloudSyncCustomFilterReconciler {
    static func normalizedURL(_ url: String) -> String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func deletedURLsToMergeDuringUploadReconciliation(
        remoteDeletedURLs: Set<String>,
        localCustomURLs: Set<String>
    ) -> Set<String> {
        deletedURLsToMerge(
            remoteDeletedURLs: remoteDeletedURLs,
            liveCustomURLs: normalizedURLs(localCustomURLs)
        )
    }

    static func deletedURLsToMergeDuringRemoteApply(
        remoteDeletedURLs: Set<String>,
        remoteCustomURLs: Set<String>,
        localCustomURLs: Set<String>
    ) -> Set<String> {
        deletedURLsToMerge(
            remoteDeletedURLs: remoteDeletedURLs,
            liveCustomURLs: normalizedURLs(remoteCustomURLs).union(normalizedURLs(localCustomURLs))
        )
    }

    static func deletedURLsToClearDuringReconciliation(
        existingDeletedURLs: Set<String>,
        remoteCustomURLs: Set<String>,
        localCustomURLs: Set<String>
    ) -> Set<String> {
        normalizedURLs(existingDeletedURLs)
            .intersection(normalizedURLs(remoteCustomURLs).union(normalizedURLs(localCustomURLs)))
    }

    private static func deletedURLsToMerge(
        remoteDeletedURLs: Set<String>,
        liveCustomURLs: Set<String>
    ) -> Set<String> {
        normalizedURLs(remoteDeletedURLs).filter { remoteURL in
            !remoteURL.isEmpty && !liveCustomURLs.contains(remoteURL)
        }
    }

    private static func normalizedURLs(_ urls: Set<String>) -> Set<String> {
        Set(urls.map(normalizedURL).filter { !$0.isEmpty })
    }
}
