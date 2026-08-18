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
let field = try read("wBlock/ApplyProgressField.swift")
let model = try read("wBlock/ApplyChangesViewModel.swift")

require(model.contains("struct ApplyProgressPresentation"), "missing presentation model")
require(model.contains("static func make(from state: ApplyChangesState)"), "presentation must be derived from apply state")
require(model.contains("rowDetail(for:"), "each phase row must carry its own detail")
require(view.contains("ApplyProgressField"), "progress must use the shared field")
require(view.contains("displayedProgress"), "the field must animate a displayed progress value")
require(field.contains("ProgressView(value: displayedProgress)"), "progress must use the system determinate ProgressView")
require(field.contains("ProgressView()"), "the active row must use the system spinner")
require(field.contains("checkmark.circle.fill"), "completed rows must use the system checkmark")
require(!field.contains("ApplyProgressTrack"), "custom-drawn tracks must stay out of the native field")
require(!field.contains("ApplyPhaseRail"), "custom phase rails must stay out of the native field")
require(!view.contains("progressOverviewCard"), "mid-run StatCards must be gone")
require(!view.contains("private struct PhaseRow"), "legacy phase rows must be removed")
require(view.contains("prefersLarge: mode == .review"), "only the update review list should request a large sheet")
require(!view.contains("mode == .review || mode == .progress"), "progress should not force a large sheet")

print("PASS: apply progress field contract")
