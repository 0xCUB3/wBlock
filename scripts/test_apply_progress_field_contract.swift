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
let compat = try read("wBlock/SwiftUICompatibility.swift")

require(model.contains("struct ApplyProgressPresentation"), "missing presentation model")
require(model.contains("static func make(from state: ApplyChangesState)"), "presentation must be derived from apply state")
require(model.contains("rowDetail(for:"), "each phase row must carry its own detail")
require(model.contains("let accessory: String?"), "short fractions must stay off the detail line")
require(model.contains("var progressLabel"), "the bar caption must come from the same snapshot as the fill")
require(model.contains("if step.status == .failed"), "failed rows must not repeat the failure card")
require(view.contains("ApplyProgressField(presentation: presentation)"), "progress must use the shared field")
require(!view.contains("displayedProgress"), "a lagged displayed progress value can drift from the status list")
require(field.contains("ProgressView(value: presentation.progress)"), "the bar must bind to the live presentation fill")
require(field.contains("presentation.progressLabel"), "the bar caption must describe that same fill")
require(field.contains("ProgressView()"), "the active row must use the system spinner")
require(field.contains("checkmark.circle.fill"), "completed rows must use the system checkmark")
require(field.contains("node.accessory"), "short fractions must trail the title, not the list name")
require(field.contains(".fixedSize(horizontal: false, vertical: true)"), "titles and details must wrap on a narrow sheet")
require(!field.contains("lineLimit(1)\n                Spacer"), "phase titles must not truncate beside the current list")
require(!field.contains("groupedRows"), "iOS must not wrap the list in a second card")
require(!field.contains("secondarySystemGroupedBackground"), "custom grouped fills must stay out of the field")
require(!field.contains("ApplyProgressTrack"), "custom-drawn tracks must stay out of the native field")
require(!field.contains("ApplyPhaseRail"), "custom phase rails must stay out of the native field")
require(!field.contains("displayedProgress"), "the field must not keep a second progress value")
require(!view.contains("progressOverviewCard"), "mid-run StatCards must be gone")
require(!view.contains("private struct PhaseRow"), "legacy phase rows must be removed")
require(view.contains("prefersLarge: mode == .review"), "only the update review list should request a large sheet")
require(view.contains("prefersTall: mode == .progress || mode == .failed"), "progress must open taller than medium so the phase list is not clipped")
require(!view.contains("mode == .review || mode == .progress"), "progress should not force a large sheet")
require(compat.contains(".height(560)"), "the tall detent must clear the stacked phase list")
let progressCase = view.components(separatedBy: "case .progress:").dropFirst().first?
    .components(separatedBy: "case .").first ?? ""
require(progressCase.contains("ScrollView"), "progress content must scroll if the phase list is taller than the sheet")
require(!field.contains(".accessibilityLabel(presentation.title)"), "the field must not announce the active phase on top of the rows")
require(field.contains(".accessibilityValue(node.accessibilityValue)"), "rows must announce their own status")
require(model.contains("return String(localized: \"Failed\")"), "failed rows must stay distinguishable to VoiceOver")

print("PASS: apply progress field contract")
