import Foundation
import wBlockCoreService

enum CloudSyncRemoteUserScriptReconciler {
    private static let retiredTinyShieldPrefix =
        "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/grouped/"
    private static let retiredYouTubeAdBlockURL =
        "https://raw.githubusercontent.com/SysAdminDoc/YoutubeAdblock/main/YoutubeAdblock.user.js"
    private static let legacyBundledURLs: [String: String] = [
        "https://bundled.wblock.invalid/tube-cleaner.user.js": "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/tube-cleaner/dist/tube-cleaner.user.js",
        "https://bundled.wblock.invalid/player-cleaner.user.js": "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/player-cleaner/dist/player-cleaner.user.js",
        "https://bundled.wblock.invalid/dark-reader.user.js": "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/dark-reader/dist/dark-reader.user.js",
    ]

    static func normalizedURL(_ url: String) -> String {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix(retiredTinyShieldPrefix) || isRetiredYouTubeScript(normalized) {
            return ""
        }
        return legacyBundledURLs[normalized] ?? normalized
    }

    private static func isRetiredYouTubeScript(_ urlString: String) -> Bool {
        urlString == retiredYouTubeAdBlockURL
            || URL(string: urlString).map(RetiredUserScriptSources.isYouTubeClassic) == true
    }

    static func canonicalURL(_ url: String) -> URL? {
        let normalized = normalizedURL(url)
        guard !normalized.isEmpty else { return nil }
        return URL(string: normalized)
    }

    static func deletedURLsToClearDuringUploadReconciliation(
        existingDeletedURLs: Set<String>,
        localRemoteScriptURLs: Set<String>,
        locallyAddedURLs: Set<String> = []
    ) -> Set<String> {
        normalizedURLs(existingDeletedURLs)
            .intersection(normalizedURLs(localRemoteScriptURLs))
            .intersection(normalizedURLs(locallyAddedURLs))
    }

    static func deletedURLsToMergeDuringUploadReconciliation(
        remoteDeletedURLs: Set<String>,
        localRemoteScriptURLs: Set<String>,
        locallyAddedURLs: Set<String> = []
    ) -> Set<String> {
        deletedURLsToMerge(
            remoteDeletedURLs: remoteDeletedURLs,
            liveRemoteScriptURLs: normalizedURLs(localRemoteScriptURLs)
                .intersection(normalizedURLs(locallyAddedURLs))
        )
    }

    static func deletedURLsToMergeDuringRemoteApply(
        remoteDeletedURLs: Set<String>,
        remoteRemoteScriptURLs: Set<String>,
        localRemoteScriptURLs: Set<String>,
        locallyAddedURLs: Set<String> = []
    ) -> Set<String> {
        deletedURLsToMerge(
            remoteDeletedURLs: remoteDeletedURLs,
            liveRemoteScriptURLs: normalizedURLs(remoteRemoteScriptURLs)
                .union(normalizedURLs(localRemoteScriptURLs).intersection(normalizedURLs(locallyAddedURLs)))
        )
    }

    static func deletedURLsToClearDuringReconciliation(
        existingDeletedURLs: Set<String>,
        remoteRemoteScriptURLs: Set<String>,
        localRemoteScriptURLs: Set<String>,
        locallyAddedURLs: Set<String> = []
    ) -> Set<String> {
        normalizedURLs(existingDeletedURLs)
            .intersection(normalizedURLs(remoteRemoteScriptURLs).union(
                normalizedURLs(localRemoteScriptURLs).intersection(normalizedURLs(locallyAddedURLs))
            ))
    }

    /// A successful sync acknowledges only the local add generation it actually
    /// observed. A remove/re-add while CloudKit is suspended must remain pending.
    static func additionsAfterAcknowledging(
        current: [String: String],
        snapshot: [String: String],
        syncedURLs: Set<String>
    ) -> [String: String] {
        let synced = normalizedURLs(syncedURLs)
        return current.filter { url, generation in
            !synced.contains(normalizedURL(url)) || snapshot[url] != generation
        }
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
