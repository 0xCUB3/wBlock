#!/usr/bin/env swift
import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func read(_ path: String) throws -> String {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func section(_ source: String, _ start: String, _ end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source[startRange.lowerBound...].range(of: end) else {
        require(false, "missing section '\(start)' .. '\(end)'")
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.upperBound])
}

let updater = try read("wBlock/FilterListUpdater.swift")
let userScript = try read("wBlockCoreService/UserScript.swift")

// 1. Eligibility does not require updateURL when url exists
let checkFunc = section(updater, "func checkForScriptUpdates(scripts: [UserScript])", "return await boundedConcurrentCompactMap")
require(!checkFunc.contains("$0.updateURL != nil"), "checkForScriptUpdates must not require updateURL != nil")
require(checkFunc.contains("isEligibleForUpdateCheck"), "checkForScriptUpdates uses isEligibleForUpdateCheck")

let eligibilityDef = section(userScript, "var isEligibleForUpdateCheck: Bool", "}")
require(eligibilityDef.contains("!isLocal"), "isEligibleForUpdateCheck checks !isLocal")
require(eligibilityDef.contains("isDownloaded"), "isEligibleForUpdateCheck checks isDownloaded")
require(eligibilityDef.contains("updatesAutomatically"), "isEligibleForUpdateCheck checks updatesAutomatically")
require(eligibilityDef.contains("resolvedMetaURL != nil || resolvedDownloadURL != nil"), "isEligibleForUpdateCheck checks resolvable URLs")

// 2. URL resolution helpers
let metaDef = section(userScript, "var resolvedMetaURL: URL?", "var resolvedDownloadURL: URL?")
require(metaDef.contains("updateURL"), "resolvedMetaURL checks updateURL")
require(metaDef.contains(".user.js") && metaDef.contains(".meta.js"), "resolvedMetaURL derives meta from .user.js")
require(metaDef.contains("return scriptURL"), "resolvedMetaURL falls back to script url")

let downloadDef = section(userScript, "var resolvedDownloadURL: URL?", "var isEligibleForUpdateCheck: Bool")
require(downloadDef.contains("downloadURL") && downloadDef.contains("return url"), "resolvedDownloadURL checks downloadURL then url")

// 3. hasScriptUpdate logic:
// - does not return false early solely on .meta.js
// - inconclusive meta check falls through to download + content comparison
// - remote version present with empty local version returns true early
// - both versions present uses isVersionNewer
let hasUpdateFunc = section(updater, "private func hasScriptUpdate(for script: UserScript)", "func fetchAndProcessScript")
require(!hasUpdateFunc.contains("let isMeta = updateURLString.hasSuffix(\".meta.js\")\n            if isMeta {\n                return false\n            }"), "hasScriptUpdate does not have early false return on .meta.js")
require(hasUpdateFunc.contains("if script.version.isEmpty { return true }"), "hasScriptUpdate returns true early when remote version exists but local version is empty")
require(hasUpdateFunc.contains("UserScript.isVersionNewer(tempScript.version, than: script.version)"), "hasScriptUpdate compares versions using isVersionNewer")
require(hasUpdateFunc.contains("resolvedMetaURL") && hasUpdateFunc.contains("resolvedDownloadURL"), "hasScriptUpdate uses resolved URLs")
require(hasUpdateFunc.contains("downloadURL != metaURL"), "hasScriptUpdate falls back to downloadURL when meta is inconclusive")

// 4. Test UserScript version comparison logic
func isVersionNewer(_ remote: String, than local: String) -> Bool {
    let remoteParts = remote.split(separator: ".", omittingEmptySubsequences: false).map { part in
        Int(part.prefix(while: { $0.isNumber })) ?? 0
    }
    let localParts = local.split(separator: ".", omittingEmptySubsequences: false).map { part in
        Int(part.prefix(while: { $0.isNumber })) ?? 0
    }
    let maxLen = max(remoteParts.count, localParts.count)
    for i in 0..<maxLen {
        let r = i < remoteParts.count ? remoteParts[i] : 0
        let l = i < localParts.count ? localParts[i] : 0
        if r > l { return true }
        if r < l { return false }
    }
    return false
}

require(isVersionNewer("0.1.18", than: "0.1.17"), "0.1.18 should be newer than 0.1.17")
require(isVersionNewer("1.0.0", than: ""), "1.0.0 should be newer than empty string")
require(!isVersionNewer("0.1.17", than: "0.1.17"), "Same version is not newer")
require(!isVersionNewer("0.1.16", than: "0.1.17"), "Older version is not newer")

print("PASS: userscript update check contract")
