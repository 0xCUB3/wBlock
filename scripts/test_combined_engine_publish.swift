import Foundation

let source = try String(contentsOfFile: "wBlockCoreService/wBlockCoreService.swift", encoding: .utf8)

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func position(of needle: String) -> String.Index {
    guard let range = source.range(of: needle) else {
        fputs("FAIL: missing \(needle)\n", stderr)
        exit(1)
    }
    return range.lowerBound
}

let requestRecord = position(of: "let requestToken = try recordCombinedEngineRequest(at: baseURL)")
let buildLock = position(of: "try withCombinedEngineBuildLock(at: baseURL)")
let initialCheck = position(of: "let skipped = try withEngineCriticalSection")
let temporaryBuild = position(of: "let temporaryBuild = try buildTemporaryEngine")
let commitSection = position(of: "let published = try withEngineCriticalSection")
let requestCommitLock = position(of: "try withCombinedEngineRequestLock(at: baseURL) {")
let tokenCheck = position(of: "guard latestCombinedEngineRequestToken(at: baseURL) == requestToken else")
let markerCreation = position(of: "try Data().write(to: migrationMarkerURL, options: .atomic)")
let metaInvalidation = position(of: "try invalidateExistingEngineMeta(at: baseURL)")
let replacement = position(of: "for fileName in engineStorageFileNames where fileName != Schema.ENGINE_META_FILE_NAME")
let metaReplacement = position(of: "temporaryBuild.directory.appendingPathComponent(Schema.ENGINE_META_FILE_NAME)")
let publishedValidation = position(of: "guard validatePublishedEngineFiles(at: baseURL, artifactDigests: temporaryBuild.artifactDigests) else")
let markerWrite = position(of: "to: baseURL.appendingPathComponent(combinedEngineMarkerFileName)")
let markerRemoval = position(of: "try FileManager.default.removeItem(at: migrationMarkerURL)")
let skipStart = position(of: "private static func canSkipCombinedEnginePublish")
let skipEnd = position(of: "private static func validatePublishedEngineFiles")

for needle in [
    "private static func withCombinedEngineBuildLock",
    "combinedEngineBuildLockTimeout: TimeInterval = 120",
    "engineFileLockTimeout: TimeInterval = 2",
    "private static func withEngineCriticalSection",
    "private static func validateTemporaryEngine",
    "private static func validatePublishedEngineFiles",
    "private static func engineArtifactDigests",
    "artifactDigests: [String: String]",
    "EngineMeta.fromData(metaData)",
    "FilterRuleStorage(\n                fileURL:",
    "FilterEngine(\n                storage: storage,\n                indexFileURL:",
    "try Data().write(to: migrationMarkerURL, options: .atomic)",
    "options: .atomic\n        )",
] {
    _ = position(of: needle)
}

require(requestRecord < buildLock,
        "the unique request must be recorded before waiting for the build lock")
require(buildLock < initialCheck && initialCheck < temporaryBuild && temporaryBuild < commitSection,
        "the build lock must cover check, compilation, and commit")
require(requestCommitLock < tokenCheck && tokenCheck < position(of: "try publishEngineFiles("),
        "commit must hold the request lock while checking the latest token")
require(markerCreation < metaInvalidation && metaInvalidation < replacement && replacement < metaReplacement,
        "existing meta must be invalidated before other artifacts and replaced last")
require(metaReplacement < publishedValidation && publishedValidation < markerWrite,
        "the new meta must be validated before the combined marker")
require(markerWrite < markerRemoval,
        "the migration marker must be removed only after the combined marker is atomically written")
require(source.contains("Set(marker.artifactDigests.keys) == Set(engineStorageFileNames)"),
        "the marker must name exactly the four published artifacts")
require(source.contains("engineArtifactDigests(at: baseURL)) == artifactDigests"),
        "skip validation must hash every published artifact")
require(source.contains("Schema.FILTER_RULE_STORAGE_FILE_NAME,\n        Schema.FILTER_ENGINE_INDEX_FILE_NAME,\n        Schema.RULES_FILE_NAME,\n        Schema.ENGINE_META_FILE_NAME"),
        "the marker must cover the exact storage, index, rules, and meta files")
let skipBody = source[skipStart..<skipEnd]
require(!skipBody.contains("FilterRuleStorage") && !skipBody.contains("iterator.next()"),
        "skip validation must not decode every rule")
require(source.contains("while iterator.next() != nil") && source.contains("decodedRuleCount == storage.count"),
        "temporary validation must detect truncated or corrupt stored rules")
require(source.contains("marker.rulesHash == fingerprint.rulesHash") && source.contains("marker.fingerprint == fingerprint.value"),
        "input, platform, schema, and marker format changes must invalidate the marker")
require(source.contains("filePath: baseURL.appendingPathComponent(combinedEngineBuildLockFileName).path"),
        "the publisher needs a separate cross-process build lock")
require(source.contains("filePath: baseURL.appendingPathComponent(combinedEngineRequestLockFileName).path"),
        "request tokens need a separate short-lived cross-process lock")
require(source.contains("combinedEngineRequestLockTimeout: TimeInterval = 2"),
        "request-token coordination must not hold the build lock timeout")
require(source.contains("try Data(token.utf8).write") && source.contains("options: .atomic"),
        "latest request tokens must be atomically recorded")
require(source.contains("os_log(.info, \"Abandoning superseded combined filter engine publish\")"),
        "superseded builds must abandon their temporary output")
require(source.contains("try FileManager.default.removeItem(at: metaURL)"),
        "meta invalidation must remove the old readable metadata")
require(!source.contains("NSFileCoordinator"),
        "the shared FileLock must remain the cross-process coordination primitive")

let publishStart = position(of: "public static func publishCombinedFilterEngine")
let publishEnd = position(of: "public static func buildCombinedFilterEngine")
let publishBody = source[publishStart..<publishEnd]
require(!publishBody.contains("WebExtensionGate.shared.withLock"),
        "WebExtensionGate must not cover compilation")

// Behavior guardrail: a request recorded while an older request compiles must supersede it,
// while the prior published engine remains untouched until the newer request commits.
struct RequestLedger {
    private(set) var latest: String?
    mutating func record(_ token: String) { latest = token }
    func canCommit(_ token: String) -> Bool { latest == token }
}

var ledger = RequestLedger()
var publishedEngine = "prior-engine"
ledger.record("older")
ledger.record("newer")
if ledger.canCommit("older") {
    publishedEngine = "older-engine"
}
require(!ledger.canCommit("older"), "an older request must be rejected after a later request is recorded")
require(publishedEngine == "prior-engine", "superseded output must not replace the prior engine")
require(ledger.canCommit("newer"), "the latest request must remain publishable")

print("PASS: combined engine publish static and behavior guardrails")
