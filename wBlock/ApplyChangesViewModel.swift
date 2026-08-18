//
//  ApplyChangesViewModel.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI

/// Presentation mode for the unified Apply Changes sheet.
enum ApplyChangesSheetMode: Equatable {
    case review
    case progress
    case result
    case failed
}

/// The phases the apply flow walks through.
enum ApplyChangesPhase: String, CaseIterable, Identifiable {
    case updating
    case scripts
    case reading
    case converting
    case reloading
    case saving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .updating: return String(localized: "Checking for Updates")
        case .scripts: return String(localized: "Updating Scripts")
        case .reading: return String(localized: "Reading Files")
        case .converting: return String(localized: "Converting Rules")
        case .reloading: return String(localized: "Reloading Extensions")
        case .saving: return String(localized: "Saving & Building")
        }
    }
}

/// Status flags for each phase row.
enum ApplyChangesPhaseStatus: Equatable {
    case pending
    case active
    case complete
    case failed
}

/// Model used to render the phase list in the progress sheet.
struct ApplyChangesPhaseProgress: Equatable, Identifiable {
    let phase: ApplyChangesPhase
    var status: ApplyChangesPhaseStatus

    var id: ApplyChangesPhase { phase }
}

/// Summary statistics surfaced once the run finishes.
struct ApplyChangesSummary: Equatable {
    var sourceRules: Int
    var safariRules: Int
    var conversionTime: String
    var reloadTime: String
}

/// Consolidated state for the apply progress presentation.
struct ApplyChangesState: Equatable {
    var mode: ApplyChangesSheetMode = .progress
    var isLoading: Bool = false
    var statusMessage: String = ""
    var failureMessage: String = ""
    /// Non-fatal issues shown on the result screen (reload failures, etc.).
    var resultWarning: String = ""
    var currentFilterName: String = ""
    var scriptsUpdatedCount: Int = 0
    var scriptsFailedCount: Int = 0
    /// Total number of blocker targets for the current platform (typically 5).
    var totalCount: Int = 0
    /// Per-phase progress for target-based phases.
    var convertingDone: Int = 0
    var reloadingDone: Int = 0
    var phaseProgress: Double = 0
    var filterUpdatesFound: Int = 0
    var phases: [ApplyChangesPhaseProgress] = ApplyChangesPhase.allCases.map {
        ApplyChangesPhaseProgress(phase: $0, status: .pending)
    }
    var summary: ApplyChangesSummary? = nil

    var totalUpdatesFound: Int {
        filterUpdatesFound + scriptsUpdatedCount
    }
}

private extension ClosedRange where Bound == Double {
    func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(lowerBound, value), upperBound)
    }
}

/// Dedicated ViewModel for the apply changes sheet.
/// Keeps the API surface identical to the existing manager while greatly simplifying state updates.
@MainActor
class ApplyChangesViewModel: ObservableObject {
    @Published private(set) var state = ApplyChangesState()

    // MARK: - Public API expected by AppFilterManager

    func presentReview() {
        state = ApplyChangesState(mode: .review)
    }

    func beginProgressRun() {
        state = ApplyChangesState(
            mode: .progress,
            isLoading: true,
            statusMessage: String(localized: "Checking for updates...")
        )
        resetPhases()
    }

    func updateIsLoading(_ isLoading: Bool) {
        state.isLoading = isLoading
        if isLoading {
            if state.mode != .progress {
                state.mode = .progress
            }
            state.failureMessage = ""
            state.summary = nil
            resetPhases()
        }
    }

    func updatePhaseCompletion(
        updating: Bool? = nil,
        scripts: Bool? = nil,
        reading: Bool? = nil,
        converting: Bool? = nil,
        reloading: Bool? = nil,
        saving: Bool? = nil
    ) {
        if let updating { setPhase(.updating, isComplete: updating) }
        if let scripts { setPhase(.scripts, isComplete: scripts) }
        if let reading { setPhase(.reading, isComplete: reading) }
        if let converting { setPhase(.converting, isComplete: converting) }
        if let reloading { setPhase(.reloading, isComplete: reloading) }
        if let saving { setPhase(.saving, isComplete: saving) }
    }

    func updateCurrentFilter(_ name: String) {
        guard name != state.currentFilterName else { return }
        state.currentFilterName = name
    }

    func updateProcessedCount(_ processed: Int, total: Int) {
        let clampedTotal = max(0, total)
        guard clampedTotal != state.totalCount else { return }
        state.totalCount = clampedTotal
    }

    func updateConvertingDone(_ done: Int) {
        let clamped = max(0, done)
        guard clamped != state.convertingDone else { return }
        state.convertingDone = clamped
    }

    func updateReloadingDone(_ done: Int) {
        let clamped = max(0, done)
        guard clamped != state.reloadingDone else { return }
        state.reloadingDone = clamped
    }

    func updatePhaseProgress(_ progress: Double) {
        state.phaseProgress = (0...1).clamp(progress)
    }

    func updateStageDescription(_ description: String) {
        guard description != state.statusMessage else { return }
        state.statusMessage = description
    }

    func updateFilterUpdatesFound(_ count: Int) {
        let clamped = max(0, count)
        guard clamped != state.filterUpdatesFound else { return }
        state.filterUpdatesFound = clamped
    }

    func updateScriptsUpdateResult(updated: Int, failed: Int) {
        let updatedClamped = max(0, updated)
        let failedClamped = max(0, failed)
        state.scriptsUpdatedCount = updatedClamped
        state.scriptsFailedCount = failedClamped
    }

    func updateStatistics(
        sourceRules: Int,
        safariRules: Int,
        conversionTime: String,
        reloadTime: String,
        statusMessage: String? = nil,
        resultWarning: String? = nil
    ) {
        state.summary = ApplyChangesSummary(
            sourceRules: sourceRules,
            safariRules: safariRules,
            conversionTime: conversionTime,
            reloadTime: reloadTime
        )
        state.isLoading = false

        // Never let a summary overwrite a hard failure (e.g. advanced engine publish failed).
        if state.mode == .failed {
            if let statusMessage, !statusMessage.isEmpty {
                state.statusMessage = statusMessage
            }
            return
        }

        markAllPhasesComplete()
        state.mode = .result
        state.failureMessage = ""
        state.resultWarning = resultWarning ?? ""
        if let statusMessage, !statusMessage.isEmpty {
            state.statusMessage = statusMessage
        }
    }

    func markFailed(message: String) {
        state.mode = .failed
        state.isLoading = false
        state.failureMessage = message
        state.statusMessage = message
        state.resultWarning = ""

        if let activeIndex = state.phases.firstIndex(where: { $0.status == .active }) {
            var phases = state.phases
            phases[activeIndex].status = .failed
            state.phases = phases
        }
    }

    // MARK: - Helpers

    private func resetPhases() {
        state.phases = ApplyChangesPhase.allCases.map { phase in
            ApplyChangesPhaseProgress(phase: phase, status: phase == .updating ? .active : .pending)
        }
    }

    private func markAllPhasesComplete() {
        state.phases = state.phases.map { phase in
            var updated = phase
            if updated.status != .failed {
                updated.status = .complete
            }
            return updated
        }
    }

    private func setPhase(_ phase: ApplyChangesPhase, isComplete: Bool) {
        updatePhase(phase) { phaseProgress in
            phaseProgress.status = isComplete ? .complete : .active
        }

        if isComplete {
            activateNextPendingPhase(after: phase)
        } else {
            resetPhasesAfter(phase)
        }
    }

    private func updatePhase(_ phase: ApplyChangesPhase, mutate: (inout ApplyChangesPhaseProgress) -> Void) {
        guard let index = state.phases.firstIndex(where: { $0.phase == phase }) else { return }
        var mutablePhases = state.phases
        mutate(&mutablePhases[index])
        state.phases = mutablePhases
    }

    private func activateNextPendingPhase(after phase: ApplyChangesPhase) {
        guard let currentIndex = state.phases.firstIndex(where: { $0.phase == phase }) else { return }
        state.phaseProgress = 0
        var mutablePhases = state.phases

        if let nextIndex = mutablePhases[currentIndex...].dropFirst().firstIndex(where: { $0.status == .pending }) {
            mutablePhases[nextIndex].status = .active
        }

        state.phases = mutablePhases
    }

    private func resetPhasesAfter(_ phase: ApplyChangesPhase) {
        guard let currentIndex = state.phases.firstIndex(where: { $0.phase == phase }) else { return }
        var mutablePhases = state.phases

        for index in mutablePhases.indices where index > currentIndex {
            if mutablePhases[index].status == .complete {
                mutablePhases[index].status = .pending
            }
        }

        state.phases = mutablePhases
    }
}


/// Derived, testable snapshot of the apply sheet's live progress field.
struct ApplyProgressPresentation: Equatable {
    struct Node: Equatable, Identifiable {
        let phase: ApplyChangesPhase
        let status: ApplyChangesPhaseStatus
        let detail: String?
        var id: ApplyChangesPhase { phase }
    }

    let nodes: [Node]
    let title: String
    let detail: String?
    let fractionLabel: String?
    let progress: Double
    let isFailed: Bool

    var progressLabel: String {
        Self.percentString(progress)
    }

    var accessibilityValue: String {
        var parts: [String] = []
        if let detail, !detail.isEmpty {
            parts.append(detail)
        }
        if let fractionLabel, !fractionLabel.isEmpty {
            parts.append(fractionLabel)
        }
        parts.append(progressLabel)
        return parts.joined(separator: ", ")
    }

    static func make(from state: ApplyChangesState) -> ApplyProgressPresentation {
        let focused = focusedStep(in: state)
        let nodes = state.phases.map { step in
            Node(
                phase: step.phase,
                status: step.status,
                detail: rowDetail(for: step, state: state)
            )
        }
        return ApplyProgressPresentation(
            nodes: nodes,
            title: focused?.phase.title ?? String(localized: "Apply Changes"),
            detail: focused.flatMap { detail(for: $0, state: state) },
            fractionLabel: focused.flatMap { fractionLabel(for: $0, state: state) },
            progress: progress(from: state),
            isFailed: state.mode == .failed || focused?.status == .failed
        )
    }

    static func focusedStep(in state: ApplyChangesState) -> ApplyChangesPhaseProgress? {
        if let failed = state.phases.first(where: { $0.status == .failed }) {
            return failed
        }
        if let active = state.phases.first(where: { $0.status == .active }) {
            return active
        }
        return state.phases.last(where: { $0.status == .complete }) ?? state.phases.first
    }

    static func progress(from state: ApplyChangesState) -> Double {
        let phases = state.phases
        let count = Double(max(phases.count, 1))
        if phases.allSatisfy({ $0.status == .complete }) {
            return 1
        }
        guard let focused = focusedStep(in: state),
              let index = phases.firstIndex(where: { $0.phase == focused.phase }) else {
            return 0
        }
        if focused.status == .complete {
            return (0...1).clamp(Double(index + 1) / count)
        }
        return (0...1).clamp((Double(index) + localProgress(for: focused, state: state)) / count)
    }

    static func localProgress(for step: ApplyChangesPhaseProgress, state: ApplyChangesState) -> Double {
        switch step.phase {
        case .updating, .scripts:
            return (0...1).clamp(state.phaseProgress)
        case .converting:
            guard state.totalCount > 0 else { return 0 }
            return (0...1).clamp(Double(state.convertingDone) / Double(state.totalCount))
        case .reloading:
            guard state.totalCount > 0 else { return 0 }
            return (0...1).clamp(Double(state.reloadingDone) / Double(state.totalCount))
        case .reading, .saving:
            return 0.2
        }
    }

    static func percentString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        let clamped = (0...1).clamp(value)
        return formatter.string(from: NSNumber(value: clamped))
            ?? "\(Int((clamped * 100).rounded()))%"
    }

    private static func rowDetail(for step: ApplyChangesPhaseProgress, state: ApplyChangesState) -> String? {
        if step.status == .failed {
            return nil
        }
        let text = detail(for: step, state: state)
        guard step.status == .active, let fraction = fractionLabel(for: step, state: state) else {
            return text
        }
        if let text, !text.isEmpty, text != fraction {
            return "\(text) · \(fraction)"
        }
        return fraction
    }

    private static func fractionLabel(for step: ApplyChangesPhaseProgress, state: ApplyChangesState) -> String? {
        guard step.status == .active else { return nil }
        switch step.phase {
        case .updating, .scripts:
            let value = (0...1).clamp(state.phaseProgress)
            return value > 0 ? percentString(value) : nil
        case .converting:
            guard state.totalCount > 0 else { return nil }
            return "\(state.convertingDone)/\(state.totalCount)"
        case .reloading:
            guard state.totalCount > 0 else { return nil }
            return "\(state.reloadingDone)/\(state.totalCount)"
        case .reading, .saving:
            return nil
        }
    }

    private static func detail(for step: ApplyChangesPhaseProgress, state: ApplyChangesState) -> String? {
        if step.status == .failed {
            if !state.failureMessage.isEmpty {
                return state.failureMessage
            }
            return state.statusMessage.isEmpty ? nil : state.statusMessage
        }

        switch step.phase {
        case .updating:
            if step.status == .active {
                if !state.currentFilterName.isEmpty {
                    return state.currentFilterName
                }
                return state.statusMessage.isEmpty ? nil : state.statusMessage
            }
            if step.status == .complete {
                let count = state.filterUpdatesFound
                if count > 0 {
                    return localizedCount("Downloaded %d updates", count: count)
                }
                return String(localized: "No updates available")
            }
            return nil
        case .scripts:
            if step.status == .active {
                let message = state.statusMessage
                if message.localizedCaseInsensitiveContains("script") {
                    return message
                }
                return nil
            }
            if step.status == .complete {
                let updated = state.scriptsUpdatedCount
                let failed = state.scriptsFailedCount
                if failed > 0 {
                    return String.localizedStringWithFormat(
                        NSLocalizedString(
                            "Updated %d, %d failed",
                            comment: "Apply changes script phase detail"
                        ),
                        updated,
                        failed
                    )
                }
                if updated > 0 {
                    return localizedCount("Updated %d scripts", count: updated)
                }
                return String(localized: "No script updates")
            }
            return nil
        case .reading:
            guard state.totalCount > 0 else { return nil }
            return localizedCount("Preparing %d extensions", count: state.totalCount)
        case .converting, .reloading:
            guard step.status == .active else { return nil }
            guard !state.currentFilterName.isEmpty else { return nil }
            return state.currentFilterName
        case .saving:
            return nil
        }
    }

    private static func localizedCount(_ key: String, count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString(key, comment: "Apply changes detail"),
            count
        )
    }
}

