//
//  ApplyChangesProgressView.swift
//  wBlock
//
//  Created by Alexander Skula on 10/09/25.
//

import SwiftUI
import wBlockCoreService

struct ApplyChangesProgressView: View {
    @ObservedObject var filterManager: AppFilterManager
    @ObservedObject var viewModel: ApplyChangesViewModel
    @Binding var isPresented: Bool

    @State private var selectedFilters: Set<UUID> = []
    @State private var selectedScripts: Set<UUID> = []
    @State private var isStartingSelectedUpdates = false

    private var mode: ApplyChangesSheetMode {
        viewModel.state.mode
    }

    private var filtersByCategory: [FilterListCategory: [FilterList]] {
        Dictionary(grouping: filterManager.availableUpdates, by: \.category)
    }

    private var visibleCategories: [FilterListCategory] {
        FilterListCategory.allCases.filter { category in
            filtersByCategory[category] != nil
                || (category == .scripts && !filterManager.availableScriptUpdates.isEmpty)
        }
    }

    private var selectedUpdateCount: Int {
        selectedFilters.count + selectedScripts.count
    }

    private var totalAvailableUpdateCount: Int {
        filterManager.availableUpdates.count + filterManager.availableScriptUpdates.count
    }

    var body: some View {
        CompatibleNavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(mode == .review ? String(localized: "Cancel") : String(localized: "Done")) {
                            isPresented = false
                        }
                        .disabled(mode == .progress)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if mode == .review {
                            Button {
                                Task { await startSelectedUpdates() }
                            } label: {
                                if isStartingSelectedUpdates {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label(
                                        String(localized: "Update & Apply"),
                                        systemImage: "arrow.triangle.2.circlepath"
                                    )
                                }
                            }
                            .disabled(selectedUpdateCount == 0 || isStartingSelectedUpdates)
                        }
                    }
                }
        }
        .applySheetPresentationCompat(prefersLarge: mode == .review || mode == .progress)
        .interactiveDismissDisabled(mode == .progress || isStartingSelectedUpdates)
        .onAppear {
            syncSelectionFromAvailableUpdates()
        }
        #if os(macOS)
        .frame(
            minWidth: 460,
            idealWidth: 500,
            maxWidth: 560,
            minHeight: mode == .progress ? 400 : (mode == .review ? 420 : 260),
            idealHeight: mode == .progress ? 440 : (mode == .review ? 500 : 320),
            maxHeight: 640
        )
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .review:
            reviewContent
        case .progress:
            VStack(alignment: .leading, spacing: 12) {
                sheetHeader
                progressOverviewCard
                phaseCard
            }
            .padding(20)
        case .result:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sheetHeader
                    if let summary = viewModel.state.summary {
                        summaryCard(summary)
                    }
                }
                .padding(20)
            }
        case .failed:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sheetHeader
                    failureCard
                    phaseCard
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private var sheetHeader: some View {
        Text(headerTitle)
            .font(.title2.weight(.semibold))
    }

    // MARK: - Review

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headerTitle)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 4)

            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString(
                        "%d update(s) available",
                        comment: "Apply changes review count"
                    ),
                    totalAvailableUpdateCount
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            List {
                ForEach(visibleCategories, id: \.self) { category in
                    Section {
                        if let filters = filtersByCategory[category] {
                            ForEach(filters, id: \.id) { filter in
                                SelectableRow(
                                    title: Text(filter.localizedDisplayName),
                                    subtitle: filter.localizedDisplayDescription,
                                    isSelected: selectedFilters.contains(filter.id)
                                ) {
                                    toggleFilter(filter)
                                }
                            }
                        }

                        if category == .scripts {
                            ForEach(filterManager.availableScriptUpdates, id: \.id) { script in
                                SelectableRow(
                                    title: Text(script.localizedDisplayName),
                                    subtitle: script.localizedDisplayDescription,
                                    isSelected: selectedScripts.contains(script.id)
                                ) {
                                    toggleScript(script)
                                }
                            }
                        }
                    } header: {
                        categoryHeader(category)
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private func categoryHeader(_ category: FilterListCategory) -> some View {
        HStack {
            Text(category.localizedName)
                .font(.headline)
            Spacer()
            Toggle(
                category.localizedName,
                isOn: Binding(
                    get: { isCategorySelected(category) },
                    set: { setCategory(category, selected: $0) }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }

    // MARK: - Progress

    private var progressOverviewCard: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                title: String(localized: "Extensions"),
                value: viewModel.state.totalCount > 0 ? viewModel.state.totalCount.formatted() : "—",
                icon: "puzzlepiece.extension"
            )
            StatCard(
                title: String(localized: "Updates"),
                value: viewModel.state.totalUpdatesFound.formatted(),
                icon: "arrow.down.circle",
                metrics: [
                    StatCardMetric(
                        value: viewModel.state.filterUpdatesFound.formatted(),
                        icon: "line.3.horizontal.decrease",
                        accessibilityLabel: String(localized: "Filters")
                    ),
                    StatCardMetric(
                        value: viewModel.state.scriptsUpdatedCount.formatted(),
                        icon: "curlybraces",
                        accessibilityLabel: String(localized: "Scripts")
                    )
                ]
            )
        }
    }

    private var phaseCard: some View {
        VStack(spacing: 2) {
            ForEach(viewModel.state.phases) { step in
                PhaseRow(
                    step: step,
                    detail: detail(for: step),
                    subProgress: subProgress(for: step.phase, status: step.status)
                )
            }
        }
    }

    // MARK: - Result

    private func summaryCard(_ summary: ApplyChangesSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    title: String(localized: "Safari Rules"),
                    value: summary.safariRules.formatted(),
                    icon: "shield.lefthalf.filled"
                )
                StatCard(
                    title: String(localized: "Source Rules"),
                    value: summary.sourceRules.formatted(),
                    icon: "doc.text"
                )
                StatCard(
                    title: String(localized: "Conversion"),
                    value: summary.conversionTime,
                    icon: "clock"
                )
                StatCard(
                    title: String(localized: "Reload"),
                    value: summary.reloadTime,
                    icon: "arrow.clockwise"
                )
            }

            if !viewModel.state.resultWarning.isEmpty {
                Label(viewModel.state.resultWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.state.scriptsFailedCount > 0 {
                Label(
                    String.localizedStringWithFormat(
                        NSLocalizedString(
                            "%d script update(s) failed",
                            comment: "Apply changes script failure caption"
                        ),
                        viewModel.state.scriptsFailedCount
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

        }
    }

    private var failureCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .imageScale(.large)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Apply Failed"))
                    .font(.title3.weight(.semibold))

                Text(failureText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func syncSelectionFromAvailableUpdates() {
        selectedFilters = Set(filterManager.availableUpdates.map(\.id))
        selectedScripts = Set(filterManager.availableScriptUpdates.map(\.id))
    }

    private func toggleFilter(_ filter: FilterList) {
        if selectedFilters.remove(filter.id) == nil {
            selectedFilters.insert(filter.id)
        }
    }

    private func toggleScript(_ script: UserScript) {
        if selectedScripts.remove(script.id) == nil {
            selectedScripts.insert(script.id)
        }
    }

    private func isCategorySelected(_ category: FilterListCategory) -> Bool {
        if category == .scripts {
            return !filterManager.availableScriptUpdates.isEmpty
                && filterManager.availableScriptUpdates.allSatisfy { selectedScripts.contains($0.id) }
        }
        guard let filters = filtersByCategory[category], !filters.isEmpty else { return false }
        return filters.allSatisfy { selectedFilters.contains($0.id) }
    }

    private func setCategory(_ category: FilterListCategory, selected: Bool) {
        if category == .scripts {
            selectedScripts = selected ? Set(filterManager.availableScriptUpdates.map(\.id)) : []
            return
        }
        guard let filters = filtersByCategory[category] else { return }
        for filter in filters {
            if selected {
                selectedFilters.insert(filter.id)
            } else {
                selectedFilters.remove(filter.id)
            }
        }
    }

    private func startSelectedUpdates() async {
        guard !isStartingSelectedUpdates else { return }
        isStartingSelectedUpdates = true
        defer { isStartingSelectedUpdates = false }

        let filtersToUpdate = filterManager.availableUpdates.filter { selectedFilters.contains($0.id) }
        let scriptsToUpdate = filterManager.availableScriptUpdates.filter { selectedScripts.contains($0.id) }

        await filterManager.downloadAndApplySelectedUpdates(
            filters: filtersToUpdate,
            scripts: scriptsToUpdate
        )
    }

    // MARK: - Copy helpers

    private var headerTitle: String {
        switch mode {
        case .review:
            return String(localized: "Available Updates")
        case .progress, .result, .failed:
            return String(localized: "Apply Changes")
        }
    }

    private var failureText: String {
        if viewModel.state.failureMessage.isEmpty {
            return String(localized: "Something went wrong while applying changes.")
        }
        return viewModel.state.failureMessage
    }

    private func detail(for step: ApplyChangesPhaseProgress) -> String? {
        switch step.phase {
        case .updating:
            if step.status == .active {
                let message = viewModel.state.statusMessage
                if !message.isEmpty {
                    return message
                }
                return nil
            }
            if step.status == .complete {
                let count = viewModel.state.filterUpdatesFound
                if count > 0 {
                    return localizedCountDetail("Downloaded %d updates", count: count)
                }
                return String(localized: "No updates available")
            }
            return nil
        case .scripts:
            if step.status == .active {
                let message = viewModel.state.statusMessage
                if message.localizedCaseInsensitiveContains("script") {
                    return message
                }
                return nil
            }
            if step.status == .complete {
                let updated = viewModel.state.scriptsUpdatedCount
                let failed = viewModel.state.scriptsFailedCount
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
                    return localizedCountDetail("Updated %d scripts", count: updated)
                }
                return String(localized: "No script updates")
            }
            return nil
        case .reading:
            guard viewModel.state.totalCount > 0 else { return nil }
            return localizedCountDetail("Preparing %d extensions", count: viewModel.state.totalCount)
        case .converting:
            guard step.status == .active else { return nil }
            guard !viewModel.state.currentFilterName.isEmpty else { return nil }
            return viewModel.state.currentFilterName
        case .saving:
            return nil
        case .reloading:
            guard step.status == .active else { return nil }
            guard !viewModel.state.currentFilterName.isEmpty else { return nil }
            return viewModel.state.currentFilterName
        }
    }

    private func localizedCountDetail(_ key: String, count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString(key, comment: "Apply changes detail"),
            count
        )
    }

    private func subProgress(for phase: ApplyChangesPhase, status: ApplyChangesPhaseStatus) -> PhaseRow.SubProgress? {
        switch phase {
        case .converting:
            guard status == .active else { return nil }

            let totalCount = viewModel.state.totalCount
            let done = viewModel.state.convertingDone
            let total = Double(max(1, totalCount))
            let fraction = Swift.min(Swift.max(Double(done) / total, 0), 1)

            if totalCount > 0, done >= totalCount {
                return nil
            }

            let label = totalCount > 0 ? "\(done)/\(totalCount)" : nil
            return PhaseRow.SubProgress(value: fraction, label: label)

        case .reloading:
            guard status == .active else { return nil }

            let totalCount = viewModel.state.totalCount
            let done = viewModel.state.reloadingDone
            let total = Double(max(1, totalCount))
            let fraction = Swift.min(Swift.max(Double(done) / total, 0), 1)

            if totalCount > 0, done >= totalCount {
                return nil
            }

            let label = totalCount > 0 ? "\(done)/\(totalCount)" : nil
            return PhaseRow.SubProgress(value: fraction, label: label)

        case .updating, .scripts, .reading, .saving:
            return nil
        }
    }
}

private struct PhaseRow: View {
    let step: ApplyChangesPhaseProgress
    let detail: String?
    let subProgress: SubProgress?

    struct SubProgress {
        let value: Double
        let label: String?
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 12) {
                statusLeading
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.phase.title)
                        .font(.subheadline)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            if let subProgress {
                HStack(spacing: 10) {
                    ProgressView(value: subProgress.value)
                        .progressViewStyle(.linear)
                        .scaleEffect(y: 1.15)

                    if let label = subProgress.label {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.leading, 30)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusLeading: some View {
        switch step.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .active:
            ProgressView()
                .controlSize(.small)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
