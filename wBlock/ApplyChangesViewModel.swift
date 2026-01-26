//
//  ApplyChangesViewModel.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI

/// The phases the apply flow walks through.
enum ApplyChangesPhase: String, CaseIterable, Identifiable {
    case updating
    case reading
    case converting
    case saving
    case reloading

    var id: String { rawValue }

    var title: String {
        switch self {
        case .updating: return "Checking for Updates"
        case .reading: return "Reading Files"
        case .converting: return "Converting Rules"
        case .saving: return "Saving & Building"
        case .reloading: return "Reloading Extensions"
        }
    }

    var systemImage: String {
        switch self {
        case .updating: return "arrow.down.circle"
        case .reading: return "folder.badge.questionmark"
        case .converting: return "gearshape.2"
        case .saving: return "square.and.arrow.down"
        case .reloading: return "arrow.clockwise"
        }
    }
}

/// Status flags for each phase row.
enum ApplyChangesPhaseStatus: Equatable {
    case pending
    case active
    case complete
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
    var ruleCountsByBlocker: [String: Int]
    var blockersApproachingLimit: Set<String>
}

/// Consolidated state for the apply progress presentation.
struct ApplyChangesState: Equatable {
    var isLoading: Bool = false
    var progress: Double = 0
    var statusMessage: String = ""
    var currentFilterName: String = ""
    var processedCount: Int = 0
    var totalCount: Int = 0
    var updatesFound: Int = 0
    var phases: [ApplyChangesPhaseProgress] = ApplyChangesPhase.allCases.map { ApplyChangesPhaseProgress(phase: $0, status: .pending) }
    var summary: ApplyChangesSummary? = nil

    var progressPercentage: Int {
        Int((0...1).clamp(progress) * 100)
    }

    var isComplete: Bool {
        summary != nil
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

    private var lastProgressValue: Double = 0
    private var lastProgressUpdate: Date = .distantPast
    private let minProgressInterval: TimeInterval = 0.05
    private let minProgressDelta: Double = 0.01

    // MARK: - Public API expected by AppFilterManager

    func updateProgress(_ progress: Float) {
        let value = (0...1).clamp(Double(progress))
        let now = Date()

        let delta = abs(value - lastProgressValue)
        if delta < minProgressDelta && now.timeIntervalSince(lastProgressUpdate) < minProgressInterval {
            return
        }

        lastProgressValue = value
        lastProgressUpdate = now
        state.progress = value
    }

    func updateIsLoading(_ isLoading: Bool) {
        state.isLoading = isLoading
        if isLoading {
            resetPhases()
            resetProgressTracking()
        }
    }

    func updatePhaseCompletion(updating: Bool? = nil, reading: Bool? = nil, converting: Bool? = nil, saving: Bool? = nil, reloading: Bool? = nil) {
        if let updating = updating { setPhase(.updating, isComplete: updating) }
        if let reading = reading { setPhase(.reading, isComplete: reading) }
        if let converting = converting { setPhase(.converting, isComplete: converting) }
        if let saving = saving { setPhase(.saving, isComplete: saving) }
        if let reloading = reloading { setPhase(.reloading, isComplete: reloading) }
    }

    func updateCurrentFilter(_ name: String) {
        guard name != state.currentFilterName else { return }
        state.currentFilterName = name
    }

    func updateProcessedCount(_ processed: Int, total: Int) {
        let clampedProcessed = max(0, processed)
        let clampedTotal = max(0, total)

        guard clampedProcessed != state.processedCount || clampedTotal != state.totalCount else { return }

        state.processedCount = clampedProcessed
        state.totalCount = clampedTotal
    }

    func updateStageDescription(_ description: String) {
        guard description != state.statusMessage else { return }
        state.statusMessage = description
    }

    func updateUpdatesFound(_ count: Int) {
        guard count != state.updatesFound else { return }
        state.updatesFound = count
    }

    func updateStatistics(
        sourceRules: Int,
        safariRules: Int,
        conversionTime: String,
        reloadTime: String,
        ruleCountsByBlocker: [String: Int],
        blockersApproachingLimit: Set<String>,
        statusMessage: String? = nil
    ) {
        state.summary = ApplyChangesSummary(
            sourceRules: sourceRules,
            safariRules: safariRules,
            conversionTime: conversionTime,
            reloadTime: reloadTime,
            ruleCountsByBlocker: ruleCountsByBlocker,
            blockersApproachingLimit: blockersApproachingLimit
        )
        markAllPhasesComplete()
        state.isLoading = false
        state.progress = 1
        lastProgressValue = 1
        lastProgressUpdate = Date()

        if let statusMessage, !statusMessage.isEmpty {
            state.statusMessage = statusMessage
        } else if state.statusMessage.isEmpty || state.statusMessage.lowercased().contains("reloading") {
            state.statusMessage = "Filters applied successfully."
        }
    }

    func reset() {
        state = ApplyChangesState()
        resetProgressTracking()
    }

    // MARK: - Helpers

    private func resetProgressTracking() {
        lastProgressValue = 0
        lastProgressUpdate = .distantPast
    }

    private func resetPhases() {
        state.phases = ApplyChangesPhase.allCases.map { phase in
            ApplyChangesPhaseProgress(phase: phase, status: phase == .updating ? .active : .pending)
        }
    }

    private func markAllPhasesComplete() {
        state.phases = state.phases.map { phase in
            var updated = phase
            updated.status = .complete
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
