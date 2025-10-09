//
//  ApplyChangesViewModel.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI
import Combine
import wBlockCoreService

/// Consolidated state for the apply changes process
struct ApplyChangesState: Equatable {
    var progress: Double = 0.0
    var isLoading: Bool = false

    // Phase completion tracking
    var isReadingComplete: Bool = false
    var isConvertingComplete: Bool = false
    var isSavingComplete: Bool = false
    var isReloadingComplete: Bool = false

    // Current phase details
    var currentFilterName: String = ""
    var processedCount: Int = 0
    var totalCount: Int = 0
    var stageDescription: String = ""

    // Statistics (shown when complete)
    var sourceRulesCount: Int = 0
    var safariRulesCount: Int = 0
    var conversionTime: String = "N/A"
    var reloadTime: String = "N/A"
    var ruleCountsByCategory: [FilterListCategory: Int] = [:]
    var categoriesApproachingLimit: Set<FilterListCategory> = []

    var isComplete: Bool {
        !isLoading && progress >= 1.0
    }

    var progressPercentage: Int {
        Int(max(0.0, min(1.0, progress)) * 100)
    }
}

/// Dedicated ViewModel for the apply changes progress view
/// Throttles rapid updates from AppFilterManager to prevent UI freezing
@MainActor
class ApplyChangesViewModel: ObservableObject {
    @Published private(set) var state = ApplyChangesState()

    private let progressSubject = PassthroughSubject<Double, Never>()
    private let phaseSubject = PassthroughSubject<PhaseUpdate, Never>()
    private let detailsSubject = PassthroughSubject<DetailUpdate, Never>()
    private var cancellables = Set<AnyCancellable>()

    enum PhaseUpdate {
        case reading(Bool)
        case converting(Bool)
        case saving(Bool)
        case reloading(Bool)
    }

    struct DetailUpdate {
        var currentFilterName: String?
        var processedCount: Int?
        var totalCount: Int?
        var stageDescription: String?
    }

    init() {
        setupThrottling()
    }

    private func setupThrottling() {
        // Throttle progress updates to 30 FPS (0.033s interval)
        // Using 'latest: true' ensures we always get the most recent value
        progressSubject
            .throttle(for: .seconds(0.033), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] progress in
                self?.state.progress = progress
            }
            .store(in: &cancellables)

        // Phase updates are less frequent, throttle at 20 FPS
        phaseSubject
            .throttle(for: .seconds(0.05), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] phase in
                self?.updatePhase(phase)
            }
            .store(in: &cancellables)

        // Detail updates throttled at 10 FPS for text changes
        detailsSubject
            .throttle(for: .seconds(0.1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] details in
                self?.updateDetails(details)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Update Methods

    func updateProgress(_ progress: Float) {
        progressSubject.send(Double(progress))
    }

    func updateIsLoading(_ isLoading: Bool) {
        state.isLoading = isLoading
    }

    func updatePhaseCompletion(reading: Bool? = nil, converting: Bool? = nil, saving: Bool? = nil, reloading: Bool? = nil) {
        if let reading = reading { phaseSubject.send(.reading(reading)) }
        if let converting = converting { phaseSubject.send(.converting(converting)) }
        if let saving = saving { phaseSubject.send(.saving(saving)) }
        if let reloading = reloading { phaseSubject.send(.reloading(reloading)) }
    }

    func updateCurrentFilter(_ name: String) {
        detailsSubject.send(DetailUpdate(currentFilterName: name))
    }

    func updateProcessedCount(_ processed: Int, total: Int) {
        detailsSubject.send(DetailUpdate(processedCount: processed, totalCount: total))
    }

    func updateStageDescription(_ description: String) {
        detailsSubject.send(DetailUpdate(stageDescription: description))
    }

    func updateStatistics(
        sourceRules: Int,
        safariRules: Int,
        conversionTime: String,
        reloadTime: String,
        ruleCountsByCategory: [FilterListCategory: Int],
        categoriesApproachingLimit: Set<FilterListCategory>
    ) {
        state.sourceRulesCount = sourceRules
        state.safariRulesCount = safariRules
        state.conversionTime = conversionTime
        state.reloadTime = reloadTime
        state.ruleCountsByCategory = ruleCountsByCategory
        state.categoriesApproachingLimit = categoriesApproachingLimit
    }

    func reset() {
        state = ApplyChangesState()
    }

    // MARK: - Private Update Handlers

    private func updatePhase(_ phase: PhaseUpdate) {
        switch phase {
        case .reading(let complete):
            state.isReadingComplete = complete
        case .converting(let complete):
            state.isConvertingComplete = complete
        case .saving(let complete):
            state.isSavingComplete = complete
        case .reloading(let complete):
            state.isReloadingComplete = complete
        }
    }

    private func updateDetails(_ details: DetailUpdate) {
        if let name = details.currentFilterName {
            state.currentFilterName = name
        }
        if let processed = details.processedCount {
            state.processedCount = processed
        }
        if let total = details.totalCount {
            state.totalCount = total
        }
        if let description = details.stageDescription {
            state.stageDescription = description
        }
    }

    deinit {
        cancellables.forEach { $0.cancel() }
    }
}
