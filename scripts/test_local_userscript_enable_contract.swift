#!/usr/bin/env swift
// Local Import userscripts must be enableable from the disk-backed idle state.
// Disabled local scripts hold no content in memory, so the enable path has to
// rehydrate from disk instead of rejecting on an empty in-memory buffer. A
// rejected enable must also drop its recorded intent, or a later sync replays
// it and the row flips on its own the next time any other row is touched.
import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let manager = try read("wBlockCoreService/UserScriptManager.swift")

guard let start = manager.range(of: "private func ensureScriptReadyForEnabling(") else {
    fputs("FAIL: ensureScriptReadyForEnabling missing\n", stderr)
    exit(1)
}
let ensureBody = String(manager[start.lowerBound...].prefix(2000))

require(
    !ensureBody.contains("guard !script.isLocal else { return !script.content.isEmpty }"),
    "local scripts must not be rejected on empty in-memory content"
)
require(ensureBody.contains("if script.isLocal {"), "local scripts need their own readiness branch")
require(
    ensureBody.contains("Self.hydrateUserScriptFromDisk(script)"),
    "local readiness must rehydrate source from disk"
)
require(
    ensureBody.contains("userScripts[currentIndex] = hydrated"),
    "the hydrated local script must replace the live array element"
)

guard let setStart = manager.range(of: "public func setUserScript(") else {
    fputs("FAIL: setUserScript missing\n", stderr)
    exit(1)
}
let setBody = String(manager[setStart.lowerBound...].prefix(2500))
require(
    setBody.contains("latestUserScriptIntentValues[userScript.id] = current.isEnabled"),
    "a failed enable must reset the recorded intent so a later sync cannot replay it"
)

print("PASS: local userscript enable contract")
