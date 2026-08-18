#!/usr/bin/env swift

import Foundation

func read(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let view = try read("wBlock/ApplyChangesProgressView.swift")
let model = try read("wBlock/ApplyChangesViewModel.swift")

require(model.contains("struct ApplyProgressPresentation"), "missing presentation model")
require(model.contains("static func make(from state: ApplyChangesState)"), "presentation must be derived from apply state")
require(model.contains("static func progress(from state: ApplyChangesState)"), "presentation must expose monotonic progress")
require(view.contains("ApplyPhaseRail"), "progress must use a compact phase rail")
require(view.contains("ApplyProgressField"), "progress must use a single focused field")
require(view.contains("ApplyProgressTrack"), "progress must use a custom track")
require(view.contains("displayedProgress"), "the field must animate a displayed progress value")
require(!view.contains("progressOverviewCard"), "mid-run StatCards must be gone")
require(!view.contains("private struct PhaseRow"), "legacy phase rows must be removed")
require(!view.contains("private var phaseCard"), "the six-row phase list must be removed")
require(view.contains("prefersLarge: mode == .review"), "only the update review list should request a large sheet")
require(!view.contains("mode == .review || mode == .progress"), "progress should not force a large sheet")
require(!view.contains("ProgressView(value:"), "determinate system ProgressView should not drive the apply field")
require(view.contains(".accessibilityValue(presentation.accessibilityValue)"), "the field must publish a combined accessibility value")
require(view.contains(".accessibilityHidden(true)"), "the decorative rail must stay hidden from VoiceOver")

print("PASS: apply progress field contract")
