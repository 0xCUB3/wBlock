import Foundation

enum CloudSyncCustomFilterReconciler {
    static func deletedURLsToMergeDuringUploadReconciliation(
        remoteDeletedURLs: Set<String>,
        localCustomURLs: Set<String>
    ) -> Set<String> {
        remoteDeletedURLs.filter { remoteURL in
            !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !localCustomURLs.contains(remoteURL)
        }
    }
}
