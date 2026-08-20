#!/usr/bin/env swift
import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let manager = try String(contentsOfFile: "wBlock/AppFilterManager.swift", encoding: .utf8)
let pipeline = try String(contentsOfFile: "wBlock/AppFilterManager+ApplyPipeline.swift", encoding: .utf8)

for needle in [
    "lastAppliedUpgradeSignatureKey",
    "currentUpgradeSignature",
    "storedUpgradeSignature",
    "persistUpgradeRebuildSignature",
    "needsRebuild",
] {
    check(manager.contains(needle), "AppFilterManager.swift is missing \(needle)")
}

check(
    manager.contains("ContentBlockerService.embeddedCompatibilityRulesVersion"),
    "AppFilterManager.swift must use ContentBlockerService.embeddedCompatibilityRulesVersion"
)

check(
    pipeline.contains("persistUpgradeRebuildSignature"),
    "ApplyPipeline.swift must call persistUpgradeRebuildSignature"
)

let markStart = manager.range(of: "func markCurrentStateApplied()")
check(markStart != nil, "markCurrentStateApplied must exist")
if let markStart {
    let afterMark = manager[markStart.lowerBound...]
    let nextFunc = afterMark.range(of: "\n    private func ", range: afterMark.index(after: markStart.upperBound)..<afterMark.endIndex)
        ?? afterMark.range(of: "\n    func ", range: afterMark.index(after: markStart.upperBound)..<afterMark.endIndex)
    let markBody = nextFunc.map { String(afterMark[..<$0.lowerBound]) } ?? String(afterMark)
    check(
        !markBody.contains("persistUpgradeRebuildSignature"),
        "persistUpgradeRebuildSignature must not appear inside markCurrentStateApplied"
    )
}

let setupStart = manager.range(of: "func setup()")
check(setupStart != nil, "setup() must exist")
if let setupStart {
    let afterSetup = manager[setupStart.lowerBound...]
    let nextFunc = afterSetup.range(of: "\n    private func ", range: afterSetup.index(after: setupStart.upperBound)..<afterSetup.endIndex)
        ?? afterSetup.range(of: "\n    func ", range: afterSetup.index(after: setupStart.upperBound)..<afterSetup.endIndex)
    let setupBody = nextFunc.map { String(afterSetup[..<$0.lowerBound]) } ?? String(afterSetup)
    check(setupBody.contains("if needsRebuild"), "setup must contain if needsRebuild")
    check(setupBody.contains("markNonSelectionChangesPending"), "setup must contain markNonSelectionChangesPending")
}

print("PASS: upgrade rebuild pending persistence")
