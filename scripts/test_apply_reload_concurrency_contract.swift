#!/usr/bin/env swift

import Foundation

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

func require(_ condition: Bool, _ message: String) {
    if !condition { fail(message) }
}

func functionBody(_ source: String, signature: String) -> String {
    guard let signatureRange = source.range(of: signature),
          let openingBrace = source.range(
            of: "{",
            range: signatureRange.upperBound..<source.endIndex
          ) else {
        fail("missing function: \(signature)")
    }

    var depth = 0
    var index = openingBrace.lowerBound
    while index < source.endIndex {
        switch source[index] {
        case "{":
            depth += 1
        case "}":
            depth -= 1
            if depth == 0 {
                return String(source[signatureRange.lowerBound...index])
            }
        default:
            break
        }
        index = source.index(after: index)
    }
    fail("unterminated function: \(signature)")
}

func requireReloadCap(in body: String, name: String) {
    require(
        body.contains("boundedConcurrentForEach"),
        "\(name) must use boundedConcurrentForEach"
    )
    require(
        !body.contains("withTaskGroup") && !body.contains("group.addTask"),
        "\(name) must not launch an unbounded task group"
    )

    let pattern = #"maxConcurrent:\s*\{\s*#if\s+os\(macOS\)\s*return\s+([0-9]+)\s*#else\s*return\s+([0-9]+)\s*#endif\s*\}\(\)"#
    let regex = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(body.startIndex..<body.endIndex, in: body)
    guard let match = regex.firstMatch(in: body, range: range),
          let macRange = Range(match.range(at: 1), in: body),
          let iosRange = Range(match.range(at: 2), in: body),
          let macCap = Int(body[macRange]),
          let iosCap = Int(body[iosRange]) else {
        fail("\(name) must declare platform-specific reload concurrency caps")
    }

    require(macCap > 0 && macCap <= 3, "\(name) macOS cap must be at most 3")
    require(iosCap == 1, "\(name) iOS cap must be 1")
}

let pipeline = try String(
    contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift",
    encoding: .utf8
)
let disabledSites = try String(
    contentsOfFile: "wBlock/AppFilterManager+DisabledSites.swift",
    encoding: .utf8
)

let applyReload = functionBody(
    pipeline,
    signature: "func reloadContentBlockers(_ targets: [ContentBlockerTargetInfo])"
)
let clearReload = functionBody(
    pipeline,
    signature: "func clearAllExtensionsAndEngine()"
)
let disabledSitesReload = functionBody(
    disabledSites,
    signature: "func reloadDisabledSitesTargetsInParallel"
)

requireReloadCap(in: applyReload, name: "reloadContentBlockers")
requireReloadCap(in: clearReload, name: "clearAllExtensionsAndEngine")
requireReloadCap(in: disabledSitesReload, name: "reloadDisabledSitesTargetsInParallel")

require(
    applyReload.contains("updateReloadingDone")
        && applyReload.contains("updateCurrentFilter")
        && applyReload.contains("allowProgressUIRefresh")
        && applyReload.contains("failApplyIfCancelled"),
    "reloadContentBlockers must preserve per-target progress and cancellation updates"
)
require(
    applyReload.contains("collected.sorted { $0.target.slot < $1.target.slot }"),
    "reloadContentBlockers must preserve slot-order result processing"
)

print("PASS: apply reload concurrency contract")
