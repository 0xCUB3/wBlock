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
require(conversion.contains("saveContentBlockerIfChanged"), "normal conversion must use save-if-changed")
require(!conversion.contains("withContentBlockerOutputLock"), "conversion must not hold the output lock")
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

let applyPipeline = try String(contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift", encoding: .utf8)
let autoUpdate = try String(contentsOfFile: "wBlockCoreService/SharedAutoUpdateManager.swift", encoding: .utf8)
require(applyPipeline.contains("saveContentBlockerIfChanged"), "pause/clear writes must use save-if-changed")
require(autoUpdate.contains("saveContentBlockerIfChanged"), "auto-update pause repair must use save-if-changed")
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

print("PASS: Safari output save-if-changed guardrails")
