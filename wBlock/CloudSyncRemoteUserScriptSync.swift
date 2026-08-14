import Foundation

enum CloudSyncRemoteUserScriptReconciler {
    private static let retiredTinyShieldPrefix =
        "https://cdn.jsdelivr.net/npm/@filteringdev/tinyshield@latest/dist/grouped/"
    private static let legacyBundledURLs: [String: String] = [
        "https://bundled.wblock.invalid/tube-cleaner.user.js": "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/tube-cleaner/dist/tube-cleaner.user.js",
        "https://bundled.wblock.invalid/player-cleaner.user.js": "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/player-cleaner/dist/player-cleaner.user.js",
        "https://bundled.wblock.invalid/dark-reader.user.js": "https://raw.githubusercontent.com/0xCUB3/wBlock-userscripts/main/packages/dark-reader/dist/dark-reader.user.js",
    ]

    static func normalizedURL(_ url: String) -> String {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix(retiredTinyShieldPrefix) { return "" }
        return legacyBundledURLs[normalized] ?? normalized
    }

    static func deletedURLsToClearDuringUploadReconciliation(
        existingDeletedURLs: Set<String>,
        localRemoteScriptURLs: Set<String>
    ) -> Set<String> {
        normalizedURLs(existingDeletedURLs)
            .intersection(normalizedURLs(localRemoteScriptURLs))
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
