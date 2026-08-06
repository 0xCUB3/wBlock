#!/usr/bin/env swift

import Foundation

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func require(_ condition: Bool, _ message: String) {
    if !condition { fail(message) }
}

let source = try String(contentsOfFile: "wBlockCoreService/wBlockCoreService.swift", encoding: .utf8)

func section(from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
    else { fail("missing source section: \(start)") }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let primitive = section(
    from: "public static func saveContentBlockerIfChanged(",
    to: "public static func saveContentBlocker("
)
require(primitive.contains("Data(contentsOf: sharedFileURL)"), "primitive must read existing output bytes")
require(primitive.contains("let outputChanged = (try? Data(contentsOf: sharedFileURL)) != data"), "comparison must be byte-for-byte")
require(primitive.contains("withContentBlockerOutputLock"), "compare/write must use the shared output lock")
require(source.contains("FileLock(filePath: lockURL.path)"), "output lock must be a cross-process FileLock")
require(primitive.contains("targetRulesFilename: targetRulesFilename"), "output lock must be deterministic per target")
require(primitive.contains("data.write(to: sharedFileURL, options: .atomic)"), "changed output must use an atomic write")
require(!primitive.contains("saveBlockerListFile"), "JSON writes must use the single save-if-changed primitive")
if let lockCall = primitive.range(of: "withContentBlockerOutputLock"),
   let compare = primitive.range(of: "let outputChanged = (try? Data(contentsOf: sharedFileURL)) != data"),
   let atomicWrite = primitive.range(of: "data.write(to: sharedFileURL, options: .atomic)") {
    require(lockCall.lowerBound < compare.lowerBound, "lock must be acquired before compare")
    require(compare.lowerBound < atomicWrite.lowerBound, "compare must precede atomic write")
} else {
    fail("missing compare/write guardrail markers")
}

let conversion = section(
    from: "public static func convertFilterFromFile(",
    to: "public static func compileTargetRules("
)
let fastUpdate = section(
    from: "public static func fastUpdateDisabledSites(",
    to: "private struct DerivedBaseRules"
)
require(conversion.contains("public static func convertFilterFromFile("), "legacy conversion API must remain public")
require(conversion.contains("throws -> (safariRulesCount: Int, advancedRulesText: String?)"), "legacy conversion API must keep its two-field result")
require(conversion.contains("static func convertFilterFromFileWithOutputChange("), "changed conversion result must use a named internal API")
require(conversion.contains("saveContentBlockerIfChanged"), "normal conversion must use save-if-changed")
require(!conversion.contains("withContentBlockerOutputLock"), "conversion must not hold the output lock")
require(fastUpdate.contains("public static func fastUpdateDisabledSites("), "legacy fast-update API must remain public")
require(fastUpdate.contains("throws -> (safariRulesCount: Int, advancedRulesText: String?)"), "legacy fast-update API must keep its two-field result")
require(fastUpdate.contains("static func fastUpdateDisabledSitesWithOutputChange("), "changed fast-update result must use a named internal API")
require(fastUpdate.contains("saveContentBlockerIfChanged"), "disabled-site fast updates must use save-if-changed")
require(fastUpdate.contains("let existingJSON = try String(contentsOf: targetURL, encoding: .utf8)"), "legacy fallback must not synthesize missing JSON")
require(fastUpdate.contains("let derived = try deriveBaseRulesFromLegacyFinalJSON(existingJSON)"), "legacy fallback must propagate corruption")
require(!fastUpdate.contains("?? \"[]\""), "legacy fallback must not erase rules on missing output")
let legacyDerivation = section(
    from: "private static func deriveBaseRulesFromLegacyFinalJSON(",
    to: "private static func isLegacyDisabledSiteIgnoreRule"
)
require(legacyDerivation.contains(") throws -> DerivedBaseRules"), "legacy derivation must throw on corruption")
require(legacyDerivation.contains("CocoaError(.fileReadCorruptFile)"), "legacy corruption must be reported")

let affinityProcessor = try String(contentsOfFile: "wBlockCoreService/SafariContentBlockerAffinityProcessor.swift", encoding: .utf8)
require(source.contains("affinityFilterIDs: Set<UUID>"), "compileTargetRules must retain the affinity ID overload")
require(source.contains("affinitySnapshot: SafariContentBlockerAffinitySnapshot"), "compileTargetRules must expose the snapshot API")
require(affinityProcessor.contains("containerURL: URL"), "affinity appending must retain the container URL overload")
require(affinityProcessor.contains("affinitySnapshot: SafariContentBlockerAffinitySnapshot"), "affinity appending must expose the snapshot API")

let applyPipeline = try String(contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift", encoding: .utf8)
let disabledSites = try String(contentsOfFile: "wBlock/AppFilterManager+DisabledSites.swift", encoding: .utf8)
let autoUpdate = try String(contentsOfFile: "wBlockCoreService/SharedAutoUpdateManager.swift", encoding: .utf8)
let webExtension = try String(contentsOfFile: "wBlockCoreService/WebExtensionRequestHandler.swift", encoding: .utf8)
require(applyPipeline.contains("saveContentBlockerIfChanged"), "pause/clear writes must use save-if-changed")
require(autoUpdate.contains("saveContentBlockerIfChanged"), "auto-update pause repair must use save-if-changed")
require(source.contains("public static func reloadIfNeeded("), "reloads must go through the marker coordinator")
require(autoUpdate.contains("groupIdentifier: GroupIdentifier.shared.value,\n                targetRulesFilename: target.rulesFilename"), "auto-update reloads must invalidate the mapped target marker")
require(autoUpdate.contains("groupIdentifier: groupIdentifier,\n                    targetRulesFilename: target.rulesFilename"), "pause repair reloads must invalidate the mapped target marker")
require(webExtension.contains("groupIdentifier: groupID,\n                        targetRulesFilename: target.rulesFilename"), "WebExtension reloads must invalidate the mapped target marker")
require(source.contains("public static func invalidateReloadMarker("), "raw reloads need an explicit marker invalidation API")
require(source.contains("if let groupIdentifier, let targetRulesFilename"), "raw reload policy must require both target mapping fields")
require(source.contains("outputDigest"), "marker must carry the exact output digest")
require(source.contains("ReloadContext"), "marker must carry reload context")
require(source.contains("FileLock(") && source.contains("containerURL.appendingPathComponent(\".\\(targetRulesFilename).lock\")"), "marker checks must use the target output lock")
require(source.contains("JSONEncoder().encode(newMarker).write(to: markerURL, options: .atomic)"), "marker writes must be atomic")
require(source.contains("try? FileManager.default.removeItem(at: markerURL)"), "failed reloads must invalidate the marker")
let reloadCoordinator = section(
    from: "public static func reloadIfNeeded(",
    to: "/// Reloads the Safari content blocker extension"
)
require(source.contains("private static let maxReloadVerificationPasses = 3"), "reload verification must be bounded")
require(source.contains("private static func reloadWithRetryRaw("), "Safari retries must have a private raw implementation")
require(source.contains("withTaskCancellationHandler"), "queued reload waiters must observe cancellation")
require(source.contains("cancelWaiter"), "canceled reload waiters must be removed")
require(reloadCoordinator.contains("await reloadWithRetryRaw("), "foreground reloads must not recursively reacquire the reload gate")
require(!reloadCoordinator.contains("await reloadWithRetry("), "foreground reloads must not call the gated public retry API")
require(reloadCoordinator.contains("for _ in 0..<maxReloadVerificationPasses"), "reload verification must use the bounded loop")
require(reloadCoordinator.contains("verifiedDigest == snapshot.outputDigest"), "state-query verification must recheck the output digest")
require(reloadCoordinator.contains("verifiedDigest == expectedDigest"), "reload verification must recheck the output digest")
require(reloadCoordinator.contains("mustReloadNewestOutput = true"), "changed output must force a reload of the newest snapshot")
require(!reloadCoordinator.contains("totalDurationMs"), "reload duration must not sum nested elapsed values")
require(!reloadCoordinator.contains("return ReloadAttemptResult(success: true, attempts: totalAttempts"), "unverified reload changes must not report success")
require(applyPipeline.contains("let reloadDurationMs = reloadSummary.durationMs"), "parallel reload duration must use wall clock")
require(!applyPipeline.contains("let reloadDurationMs = activeReloads.reduce"), "parallel reloads must not sum elapsed durations")
require(!disabledSites.contains("reloadDurationMs += result.durationMs"), "parallel reload metrics must not sum elapsed durations")
require(disabledSites.contains("Date().timeIntervalSince(reloadStartTime)"), "disabled-site reload duration must use wall clock")
require(!applyPipeline.contains("reloadDurationMs += result.durationMs"), "parallel reload metrics must not sum elapsed durations")
require(!applyPipeline.contains("saveContentBlocker("), "pause/clear writes must not bypass save-if-changed")
require(!autoUpdate.contains("saveContentBlocker("), "auto-update writes must not bypass save-if-changed")
require(source.contains("public let outputChanged: Bool"), "target outcomes must carry outputChanged")
require(applyPipeline.contains("let outputChanged: Bool"), "target metrics must carry outputChanged")

func simulatedSave(existing: Data?, desired: Data) -> (changed: Bool, writes: Int) {
    guard existing == desired else { return (true, 1) }
    return (false, 0)
}

let desired = Data("[{\"trigger\":{\"url-filter\":\"a\"}}]".utf8)
require(simulatedSave(existing: nil, desired: desired).changed, "missing output must be written")
require(simulatedSave(existing: desired, desired: desired) == (false, 0), "identical output must not be written")
require(simulatedSave(existing: Data("[]".utf8), desired: desired).changed, "changed output must be written")
require(simulatedSave(existing: Data("not-json".utf8), desired: desired).changed, "malformed output must be written")
require(
    simulatedSave(existing: Data("[ {\"trigger\":{\"url-filter\":\"a\"}} ]".utf8), desired: desired).changed,
    "semantically equal but differently encoded output must be rewritten"
)

let tempURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("safari-output-skip-\(UUID().uuidString).json")
defer { try? FileManager.default.removeItem(at: tempURL) }
func writeForTest(_ data: Data) -> Bool {
    let changed = (try? Data(contentsOf: tempURL)) != data
    if changed { try! data.write(to: tempURL, options: .atomic) }
    return changed
}
require(writeForTest(desired), "missing output must be atomically created")
require(!writeForTest(desired), "identical bytes must leave output untouched")
try! Data("not-json".utf8).write(to: tempURL)
require(writeForTest(desired), "malformed output must be atomically repaired")
require(try! Data(contentsOf: tempURL) == desired, "repair must preserve authoritative bytes")

struct Marker: Equatable {
    let output: String
    let context: String
}

struct ReloadSimulation {
    var reloads = 0
    var marker: Marker?

    mutating func reload(output: Data?, context: String, reloadSucceeds: Bool) -> (skipped: Bool, success: Bool) {
        let validOutput = output.flatMap { data in
            (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] != nil ? String(data: data, encoding: .utf8) : nil
        }
        if let validOutput, marker == Marker(output: validOutput, context: context) {
            return (true, true)
        }
        marker = nil
        reloads += 1
        guard reloadSucceeds else { return (false, false) }
        guard let validOutput else { return (false, false) }
        marker = Marker(output: validOutput, context: context)
        return (false, true)
    }
}

let outputA = Data("[{\"trigger\":{\"url-filter\":\"a\"}}]".utf8)
let outputB = Data("[{\"trigger\":{\"url-filter\":\"b\"}}]".utf8)
var simulation = ReloadSimulation()
require(simulation.reload(output: outputA, context: "v1", reloadSucceeds: true).success, "first load must reload")
require(simulation.reloads == 1, "first load must perform one reload")
require(simulation.reload(output: outputA, context: "v1", reloadSucceeds: true).skipped, "unchanged successful output must skip")
require(simulation.reloads == 1, "unchanged output must not reload")
require(simulation.reload(output: outputB, context: "v1", reloadSucceeds: true).success, "changed output must reload")
require(simulation.reloads == 2, "changed output must perform a reload")
require(!simulation.reload(output: outputA, context: "v1", reloadSucceeds: false).success, "failed reload must report failure")
require(simulation.marker == nil, "failed reload must not leave a marker")
require(simulation.reload(output: outputA, context: "v1", reloadSucceeds: true).success, "failed reload must retry")
simulation.marker = nil
require(simulation.reload(output: outputA, context: "v1", reloadSucceeds: true).success, "missing marker must reload")
require(simulation.reload(output: Data("not-json".utf8), context: "v1", reloadSucceeds: true).success == false, "corrupt output must not be marked successful")
require(simulation.reload(output: outputA, context: "v2", reloadSucceeds: true).success, "context change must reload")

print("PASS: Safari output save-if-changed and reload-skip guardrails")
