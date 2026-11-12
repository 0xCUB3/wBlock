import Foundation
import wBlockCoreService

/// An inline list is required payload content; a failed read must not become an empty cloud copy.
enum CloudSyncInlineFilterContents {
    static func read(_ fileURLs: [(String, URL)]) async throws -> [String: String] {
        try await Task.detached(priority: .utility) {
            var contents: [String: String] = [:]
            for (urlString, fileURL) in fileURLs {
                contents[urlString] = try String(contentsOf: fileURL, encoding: .utf8)
            }
            return contents
        }.value
    }
}

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

    /// The current addresses a payload's built-in list entries name usably.
    /// Two kinds of entry are left out, so they switch nothing:
    /// - An old address, unless `olderVersionsReconcile` its current one. 3.x
    ///   stores some lists under old addresses; for most it cannot match this
    ///   device's choice to its own entry and keeps its own (an AdGuard list
    ///   handed over to uBO lists stays on there).
    /// - A list the remote also has as a custom list (`customURLs`). Payloads
    ///   before 3.1.3 put custom lists in selectedURLs too (#871), so its entry
    ///   is ambiguous.
    static func usableAddresses(
        _ urls: [String], customURLs: Set<String>,
        canonicalize: (String) -> String, olderVersionsReconcile: (String) -> Bool
    ) -> [String] {
        let customs = Set(customURLs.map(canonicalize))
        return urls.compactMap { url in
            let address = canonicalize(url)
            guard !customs.contains(address), address == url || olderVersionsReconcile(address) else { return nil }
            return address
        }
    }

    /// The built-in selection a remote payload asks for, by current address:
    /// this device's change since the last sync (`baseline`) wins over the
    /// remote's (CloudSyncMerge.strings), and the remote's choice applies to the
    /// lists it names usably (usableAddresses).
    static func remoteBuiltInSelection(
        local: [String],
        baseline: [String],
        remote: [String],
        remoteKnown: [String]?,
        remoteCustomURLs: Set<String>,
        canonicalize: (String) -> String,
        olderVersionsReconcile: (String) -> Bool
    ) -> (selected: Set<String>, known: Set<String>) {
        func usable(_ urls: [String]) -> [String] {
            usableAddresses(urls, customURLs: remoteCustomURLs, canonicalize: canonicalize,
                            olderVersionsReconcile: olderVersionsReconcile)
        }
        let selected = CloudSyncMerge.strings(local: usable(local), baseline: usable(baseline), remote: usable(remote))
        return (Set(selected), Set(remoteKnown.map(usable) ?? selected))
    }

    /// The built-in selection to keep as the sync baseline after applying a
    /// remote payload, by current address. It moves to the remote's choice only
    /// for lists the remote names usably. For the rest (a 3.x payload names
    /// moved lists by addresses this device leaves out) it keeps the previous
    /// baseline's, so a change made here still reads as one and another
    /// device's later change still applies. A list neither names takes this
    /// device's choice from before the apply.
    static func baselineSelection(
        remote: (selected: [String], known: [String]?),
        previous: (selected: [String], known: [String]?),
        local: (selected: [String], known: [String]),
        remoteCustomURLs: Set<String>,
        canonicalize: (String) -> String,
        olderVersionsReconcile: (String) -> Bool
    ) -> (selected: [String], known: [String]) {
        // The remote's custom lists make only its own entries ambiguous.
        func usable(_ urls: [String], _ customURLs: Set<String>) -> Set<String> {
            Set(usableAddresses(urls, customURLs: customURLs, canonicalize: canonicalize,
                                olderVersionsReconcile: olderVersionsReconcile))
        }
        let payloads: [(source: (selected: [String], known: [String]?), customURLs: Set<String>)] =
            [(remote, remoteCustomURLs), (previous, []), ((local.selected, local.known), [])]
        let sources = payloads.map {
            (named: usable($0.source.known ?? $0.source.selected, $0.customURLs), selected: usable($0.source.selected, $0.customURLs))
        }
        let lists = sources.reduce(into: Set<String>()) { $0.formUnion($1.named) }
        let selected = lists.filter { list in sources.first { $0.named.contains(list) }!.selected.contains(list) }
        return (selected.sorted(), lists.sorted())
    }

    /// A custom list at a built-in list's address is that list: 4.0 folds such
    /// copies into the catalog entry (FilterListSetup.hydrate), and a 3.x device
    /// still sends them as custom. Importing one would add it again.
    static func isBuiltInCopy(_ url: String, builtInURLs: Set<String>, canonicalize: (String) -> String) -> Bool {
        guard let address = URL(string: canonicalize(url)) else { return false }
        let key = FilterListURLSupport.identityKey(for: address)
        return builtInURLs.contains { URL(string: $0).map(FilterListURLSupport.identityKey) == key }
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

enum CloudSyncMerge {
    /// Three-way merge of string sets: the remote set, with this device's
    /// additions and removals since the last sync (`baseline`) applied on top.
    static func strings(local: [String], baseline: [String], remote: [String]) -> [String] {
        let baselineSet = Set(baseline)
        let localSet = Set(local)
        var merged = Set(remote)
        merged.subtract(baselineSet.subtracting(localSet))
        merged.formUnion(localSet.subtracting(baselineSet))
        return merged.sorted()
    }
}
