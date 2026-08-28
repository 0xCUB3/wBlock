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

    /// A tombstone must not delete a custom list that appeared after the
    /// snapshot used to merge that tombstone. That is a local add in flight.
    static func tombstonedURLsToDelete(
        tombstonedURLs: Set<String>,
        snapshotCustomURLs: Set<String>,
        liveCustomURLs: Set<String>
    ) -> Set<String> {
        let addedSinceSnapshot = normalizedURLs(liveCustomURLs)
            .subtracting(normalizedURLs(snapshotCustomURLs))
        return normalizedURLs(tombstonedURLs).subtracting(addedSinceSnapshot)
    }

    static func deletedURLsToClearDuringReconciliation(
        existingDeletedURLMarkers: [String: TimeInterval],
        remoteCustomURLs: Set<String>,
        localCustomURLs: Set<String>,
        remoteUpdatedAt: TimeInterval
    ) -> Set<String> {
        let normalizedRemoteCustomURLs = normalizedURLs(remoteCustomURLs)
        let normalizedLocalCustomURLs = normalizedURLs(localCustomURLs)
        return Set(
            existingDeletedURLMarkers.compactMap { rawURL, deletedAt in
                let normalized = normalizedURL(rawURL)
                guard !normalized.isEmpty else { return nil }
                if normalizedLocalCustomURLs.contains(normalized) {
                    return normalized
                }
                guard remoteUpdatedAt > 0 else { return nil }
                guard normalizedRemoteCustomURLs.contains(normalized) else { return nil }
                guard deletedAt <= remoteUpdatedAt else { return nil }
                return normalized
            }
        )
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
