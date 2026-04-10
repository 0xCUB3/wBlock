import Foundation

enum CloudSyncRemoteUserScriptReconciler {
    static func normalizedURL(_ url: String) -> String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func deletedURLsToMergeDuringUploadReconciliation(
        remoteDeletedURLs: Set<String>,
        localRemoteScriptURLs: Set<String>
    ) -> Set<String> {
        deletedURLsToMerge(
            remoteDeletedURLs: remoteDeletedURLs,
            liveRemoteScriptURLs: normalizedURLs(localRemoteScriptURLs)
        )
    }

    static func deletedURLsToMergeDuringRemoteApply(
        remoteDeletedURLs: Set<String>,
        remoteRemoteScriptURLs: Set<String>,
        localRemoteScriptURLs: Set<String>
    ) -> Set<String> {
        deletedURLsToMerge(
            remoteDeletedURLs: remoteDeletedURLs,
            liveRemoteScriptURLs: normalizedURLs(remoteRemoteScriptURLs)
                .union(normalizedURLs(localRemoteScriptURLs))
        )
    }

    static func deletedURLsToClearDuringReconciliation(
        existingDeletedURLs: Set<String>,
        remoteRemoteScriptURLs: Set<String>,
        localRemoteScriptURLs: Set<String>
    ) -> Set<String> {
        normalizedURLs(existingDeletedURLs)
            .intersection(normalizedURLs(remoteRemoteScriptURLs).union(normalizedURLs(localRemoteScriptURLs)))
    }

    private static func deletedURLsToMerge(
        remoteDeletedURLs: Set<String>,
        liveRemoteScriptURLs: Set<String>
    ) -> Set<String> {
        normalizedURLs(remoteDeletedURLs).filter { remoteURL in
            !remoteURL.isEmpty && !liveRemoteScriptURLs.contains(remoteURL)
        }
    }

    private static func normalizedURLs(_ urls: Set<String>) -> Set<String> {
        Set(urls.map(normalizedURL).filter { !$0.isEmpty })
    }
}
