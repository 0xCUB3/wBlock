import Foundation
import CryptoKit
@testable import wBlockCoreService

/// Cache-hit applies and skipped reloads must avoid re-reading `.advanced.txt`
/// and re-hashing unchanged multi-MB JSON files while still invalidating
/// whenever output files, base files, disabled sites, or reload markers change.
@main
struct ContentBlockerCacheFastPathsTests {
    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fail(message)
        }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func main() async throws {
        let groupIdentifier = "group.wblock.test.cache-fast-paths.\(UUID().uuidString.prefix(8))"
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("wblock-cache-fast-paths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let target = ContentBlockerTargetManager.shared.allTargets(forPlatform: .macOS)[0]
        let list = FilterList(
            name: "fast-path-probe",
            url: URL(string: "https://example.com/fast-path.txt")!,
            category: .ads,
            isSelected: true
        )
        let listURL = container.appendingPathComponent(ContentBlockerIncrementalCache.localFilename(for: list))
        try """
        ||ads.example^
        ||tracking.example^
        example.com##.promo:has-text(Sponsored)
        """.write(to: listURL, atomically: true, encoding: .utf8)

        let ordered = ContentBlockerMappingService.orderedForCompilation([list])
        let initialDisabled = ["allowed.example"]

        // 1. Cold compile publishes both the base cache and PublishedOutputState.
        let compiled = try ContentBlockerService.compileTargetRules(
            filters: [list],
            orderedSelectedFilters: ordered,
            targetInfo: target,
            allTargets: [target],
            disabledSites: initialDisabled,
            extraRulesText: nil,
            groupIdentifier: groupIdentifier,
            containerURL: container
        )
        check(!compiled.reusedCachedBase, "cold compile must not reuse cache")
        check(compiled.outputChanged, "cold compile must write output")
        check(compiled.advancedRulesText?.contains(":has-text(Sponsored)") == true, "compiled advanced rules preserved")
        check(
            ContentBlockerIncrementalCache.hasCoherentBaseRulesCache(
                targetRulesFilename: target.rulesFilename,
                groupIdentifier: groupIdentifier,
                containerURL: container
            ),
            "base cache coherence check passes after compile"
        )

        let outputURL = container.appendingPathComponent(target.rulesFilename)
        let originalOutput = try Data(contentsOf: outputURL)

        // 2. Unchanged disabled sites hit PublishedOutputState fast path with outputChanged == false.
        let fastUnchanged = try ContentBlockerService.fastUpdateDisabledSitesWithOutputChange(
            groupIdentifier: groupIdentifier,
            targetRulesFilename: target.rulesFilename,
            disabledSites: initialDisabled,
            containerURL: container
        )
        check(!fastUnchanged.outputChanged, "unchanged fast update must hit published state")
        check(fastUnchanged.safariRulesCount == compiled.safariRulesCount, "fast path keeps exact safari rule count")
        check(fastUnchanged.advancedRulesText == compiled.advancedRulesText, "fast path preserves advanced rules text")

        // 2b. Differently formatted/duplicated disabledSites normalizing identically still hit PublishedOutputState.
        let fastNormalized = try ContentBlockerService.fastUpdateDisabledSitesWithOutputChange(
            groupIdentifier: groupIdentifier,
            targetRulesFilename: target.rulesFilename,
            disabledSites: ["  ALLOWED.EXAMPLE ", "allowed.example"],
            containerURL: container
        )
        check(!fastNormalized.outputChanged, "normalized-equal disabledSites must hit published state")
        check(fastNormalized.safariRulesCount == compiled.safariRulesCount, "normalized hit preserves rule count")
        check(fastNormalized.advancedRulesText == compiled.advancedRulesText, "normalized hit preserves advanced rules")

        // 3. Cache-hit compileTargetRules reuses base + PublishedOutputState cleanly.
        let cachedCompile = try ContentBlockerService.compileTargetRules(
            filters: [list],
            orderedSelectedFilters: ordered,
            targetInfo: target,
            allTargets: [target],
            disabledSites: initialDisabled,
            extraRulesText: nil,
            groupIdentifier: groupIdentifier,
            containerURL: container
        )
        check(cachedCompile.reusedCachedBase, "unchanged compile must reuse cached base")
        check(!cachedCompile.outputChanged, "unchanged compile must report outputChanged == false")
        check(cachedCompile.safariRulesCount == compiled.safariRulesCount, "cached compile preserves rule count")
        check(cachedCompile.advancedRulesText == compiled.advancedRulesText, "cached compile preserves advanced rules")

        // 3b. Corrupt UTF-8 in .advanced.txt triggers fallback full rebuild instead of failing apply.
        let advancedSidecarURL = container.appendingPathComponent(
            ContentBlockerIncrementalCache.baseAdvancedRulesFilename(for: target.rulesFilename)
        )
        try Data([0xFF, 0xFE, 0xFD]).write(to: advancedSidecarURL, options: .atomic)
        let rebuiltFromCorruptAdvanced = try ContentBlockerService.compileTargetRules(
            filters: [list],
            orderedSelectedFilters: ordered,
            targetInfo: target,
            allTargets: [target],
            disabledSites: initialDisabled,
            extraRulesText: nil,
            groupIdentifier: groupIdentifier,
            containerURL: container
        )
        check(!rebuiltFromCorruptAdvanced.reusedCachedBase, "corrupt .advanced.txt must fall back to full rebuild")
        check(
            rebuiltFromCorruptAdvanced.safariRulesCount == compiled.safariRulesCount,
            "fallback rebuild preserves exact safari rule count"
        )
        check(
            rebuiltFromCorruptAdvanced.advancedRulesText == compiled.advancedRulesText,
            "fallback rebuild restores valid advanced rules"
        )

        // 4. External output overwrite invalidates PublishedOutputState via outputIdentity.
        try Data("[]".utf8).write(to: outputURL, options: .atomic)
        let restored = try ContentBlockerService.fastUpdateDisabledSitesWithOutputChange(
            groupIdentifier: groupIdentifier,
            targetRulesFilename: target.rulesFilename,
            disabledSites: initialDisabled,
            containerURL: container
        )
        check(restored.outputChanged, "external output change must bypass published-state fast path")
        check(restored.safariRulesCount == compiled.safariRulesCount, "restored output keeps exact rule count")
        let restoredOutput = try Data(contentsOf: outputURL)
        check(restoredOutput == originalOutput, "external output change restores real finalized rules")

        let afterRestore = try ContentBlockerService.fastUpdateDisabledSitesWithOutputChange(
            groupIdentifier: groupIdentifier,
            targetRulesFilename: target.rulesFilename,
            disabledSites: initialDisabled,
            containerURL: container
        )
        check(!afterRestore.outputChanged, "restored output re-primes PublishedOutputState")

        // 5. Disabled-sites change invalidates PublishedOutputState, then re-primes on repeat.
        let updatedDisabled = ["allowed.example", "second.example"]
        let updatedSitesRun = try ContentBlockerService.fastUpdateDisabledSitesWithOutputChange(
            groupIdentifier: groupIdentifier,
            targetRulesFilename: target.rulesFilename,
            disabledSites: updatedDisabled,
            containerURL: container
        )
        check(updatedSitesRun.outputChanged, "changed disabledSites must update output")
        check(
            updatedSitesRun.safariRulesCount == compiled.safariRulesCount + 1,
            "adding one disabled site increases rule count by 1"
        )
        let updatedSitesRepeat = try ContentBlockerService.fastUpdateDisabledSitesWithOutputChange(
            groupIdentifier: groupIdentifier,
            targetRulesFilename: target.rulesFilename,
            disabledSites: updatedDisabled,
            containerURL: container
        )
        check(!updatedSitesRepeat.outputChanged, "repeat with updated disabledSites hits fast path")
        check(
            updatedSitesRepeat.safariRulesCount == updatedSitesRun.safariRulesCount,
            "repeat preserves updated rule count"
        )

        // 6. External base.json replacement invalidates PublishedOutputState via baseIdentity.
        let baseFilename = ContentBlockerIncrementalCache.baseRulesFilename(for: target.rulesFilename)
        let baseURL = container.appendingPathComponent(baseFilename)
        let updatedBaseJSON = Data(#"[{"trigger":{"url-filter":"ads"},"action":{"type":"block"}}]"#.utf8)
        try updatedBaseJSON.write(to: baseURL, options: .atomic)
        try "1".write(to: container.appendingPathComponent("\(baseFilename).count"), atomically: true, encoding: .utf8)
        let baseChangedRun = try ContentBlockerService.fastUpdateDisabledSitesWithOutputChange(
            groupIdentifier: groupIdentifier,
            targetRulesFilename: target.rulesFilename,
            disabledSites: updatedDisabled,
            containerURL: container
        )
        check(baseChangedRun.outputChanged, "replaced baseJSON must bypass published-state fast path")
        check(baseChangedRun.safariRulesCount == 1 + updatedDisabled.count, "replaced baseJSON count propagates")

        // 7. Missing .advanced.txt must still invalidate coherence without reading file contents.
        let advancedURL = container.appendingPathComponent(
            ContentBlockerIncrementalCache.baseAdvancedRulesFilename(for: target.rulesFilename)
        )
        try FileManager.default.removeItem(at: advancedURL)
        check(
            !ContentBlockerIncrementalCache.hasCoherentBaseRulesCache(
                targetRulesFilename: target.rulesFilename,
                groupIdentifier: groupIdentifier,
                containerURL: container
            ),
            "missing advanced sidecar must mark base cache incoherent"
        )

        // 8. ReloadMarker outputIdentity fast path + invalidation on 50,000 rules (~3.7 MB).
        let ruleFragment = #"{"trigger":{"url-filter":"example.com"},"action":{"type":"block"}}"#
        let largeRules = Data(("[" + Array(repeating: ruleFragment, count: 50_000).joined(separator: ",") + "]").utf8)
        let reloadOutputURL = container.appendingPathComponent("reload-probe.json")
        let markerURL = container.appendingPathComponent("reload-probe.json.reload-marker.json")
        try largeRules.write(to: reloadOutputURL, options: .atomic)
        let expectedLargeDigest = sha256Hex(largeRules)

        let markerWritten = try ContentBlockerService.writeReloadMarkerForTesting(
            markerURL: markerURL,
            outputURL: reloadOutputURL,
            appGroupURL: container,
            groupIdentifier: groupIdentifier
        )
        check(markerWritten, "reload marker write must succeed")

        let fastStarted = Date()
        let cachedSnapshot = try ContentBlockerService.readReloadSnapshotForTesting(
            markerURL: markerURL,
            outputURL: reloadOutputURL,
            appGroupURL: container
        )
        let fastElapsedMs = Int(Date().timeIntervalSince(fastStarted) * 1000)
        check(cachedSnapshot.markerHasIdentity, "reload marker must persist outputIdentity")
        check(cachedSnapshot.outputDigest == expectedLargeDigest, "reload snapshot must return cached digest")

        // Legacy marker without outputIdentity remains decodable and hashes the output cleanly.
        let rawMarker = try Data(contentsOf: markerURL)
        var markerObject = try JSONSerialization.jsonObject(with: rawMarker) as? [String: Any] ?? [:]
        markerObject.removeValue(forKey: "outputIdentity")
        try JSONSerialization.data(withJSONObject: markerObject).write(to: markerURL, options: .atomic)
        let legacySnapshot = try ContentBlockerService.readReloadSnapshotForTesting(
            markerURL: markerURL,
            outputURL: reloadOutputURL,
            appGroupURL: container
        )
        check(!legacySnapshot.markerHasIdentity, "legacy marker has no outputIdentity")
        check(legacySnapshot.outputDigest == expectedLargeDigest, "legacy marker recomputes digest cleanly")

        // Re-write marker with outputIdentity, then verify corrupt replacement & deletion invalidate fast path.
        _ = try ContentBlockerService.writeReloadMarkerForTesting(
            markerURL: markerURL,
            outputURL: reloadOutputURL,
            appGroupURL: container,
            groupIdentifier: groupIdentifier
        )
        let modifiedBytes = Data(#"[{"trigger":{"url-filter":"updated"},"action":{"type":"block"}}]"#.utf8)
        try modifiedBytes.write(to: reloadOutputURL, options: .atomic)
        let modifiedSnapshot = try ContentBlockerService.readReloadSnapshotForTesting(
            markerURL: markerURL,
            outputURL: reloadOutputURL,
            appGroupURL: container
        )
        check(modifiedSnapshot.outputDigest == sha256Hex(modifiedBytes), "atomic output edit must recompute digest")

        // Re-sync marker for modifiedBytes, then tamper marker digest while keeping outputIdentity & context equal:
        // proves fast path skips hashing.
        let refreshedMarkerWritten = try ContentBlockerService.writeReloadMarkerForTesting(
            markerURL: markerURL,
            outputURL: reloadOutputURL,
            appGroupURL: container,
            groupIdentifier: groupIdentifier
        )
        check(refreshedMarkerWritten, "reload marker refresh after edit must succeed")
        let modifiedDigest = sha256Hex(modifiedBytes)
        var sentinelMarker = try JSONSerialization.jsonObject(with: try Data(contentsOf: markerURL)) as? [String: Any] ?? [:]
        sentinelMarker["outputDigest"] = "sentinel-cached-digest"
        try JSONSerialization.data(withJSONObject: sentinelMarker).write(to: markerURL, options: .atomic)
        let skippedHashSnapshot = try ContentBlockerService.readReloadSnapshotForTesting(
            markerURL: markerURL,
            outputURL: reloadOutputURL,
            appGroupURL: container
        )
        check(skippedHashSnapshot.outputDigest == "sentinel-cached-digest", "matching marker identity+context must reuse stored digest without re-hashing")

        // Changing marker context must bypass fast path even when outputIdentity matches.
        var contextDict = sentinelMarker["context"] as? [String: Any] ?? [:]
        contextDict["appVersion"] = "0.0-mismatch"
        sentinelMarker["context"] = contextDict
        try JSONSerialization.data(withJSONObject: sentinelMarker).write(to: markerURL, options: .atomic)
        let mismatchedContextSnapshot = try ContentBlockerService.readReloadSnapshotForTesting(
            markerURL: markerURL,
            outputURL: reloadOutputURL,
            appGroupURL: container
        )
        check(mismatchedContextSnapshot.outputDigest == modifiedDigest, "mismatched marker context must recompute digest from disk")

        // Corrupt output must fail validation even if marker exists.
        try Data("not-valid-json".utf8).write(to: reloadOutputURL, options: .atomic)
        let corruptSnapshot = try ContentBlockerService.readReloadSnapshotForTesting(
            markerURL: markerURL,
            outputURL: reloadOutputURL,
            appGroupURL: container
        )
        check(corruptSnapshot.outputDigest == nil, "corrupt output must fail validation")

        try FileManager.default.removeItem(at: reloadOutputURL)
        let deletedSnapshot = try ContentBlockerService.readReloadSnapshotForTesting(
            markerURL: markerURL,
            outputURL: reloadOutputURL,
            appGroupURL: container
        )
        check(deletedSnapshot.outputDigest == nil, "deleted output must return nil digest")

        print("PASS: content blocker cache fast paths (reload snapshot hit in \(fastElapsedMs)ms)")
    }
}
