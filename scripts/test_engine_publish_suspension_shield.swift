#!/usr/bin/env swift

import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let service = try String(contentsOfFile: "wBlockCoreService/wBlockCoreService.swift", encoding: .utf8)

func position(of needle: String) -> String.Index {
    guard let range = service.range(of: needle) else {
        fputs("FAIL: missing \(needle)\n", stderr)
        exit(1)
    }
    return range.lowerBound
}

// The combined-engine publish holds exclusive kernel flocks on app group files
// for the entire rebuild. iOS kills any app that suspends while holding a file
// lock in a shared container (0xDEAD10CC), so every publish - including the
// manual apply pipeline, which has no auto-update suspension shield - must
// defer suspension while the locks are held and unwind (releasing the locks)
// when suspension becomes imminent.
require(service.contains("EnginePublishSuspensionShield"),
        "the engine publish needs a suspension shield")
require(service.contains("performExpiringActivity"),
        "the shield must hold an expiring-activity assertion while locks are held")
require(service.contains("case suspensionImminent"),
        "imminent suspension must abort the publish via a dedicated internal error")
require(service.contains("throw CombinedEnginePublishError.suspensionImminent"),
        "the suspension checkpoint must throw so lock scopes unwind")

let publishStart = position(of: "public static func publishCombinedFilterEngine")
let shieldCreation = position(of: "let shield = EnginePublishSuspensionShield")
let buildLock = position(of: "try withCombinedEngineBuildLock(at: baseURL)")
require(publishStart < shieldCreation && shieldCreation < buildLock,
        "the shield must be installed before the build lock is acquired")
require(service.contains("defer { shield.release() }"),
        "the assertion must lapse when the publish unwinds")
require(service.components(separatedBy: "try ensureNotSuspending()").count == 4,
        "the publish must observe imminent suspension before the skip check, the rebuild, and the commit")

print("PASS: combined engine publish suspension shield contract")
