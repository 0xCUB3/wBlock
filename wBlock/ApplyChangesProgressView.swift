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

    private var presentation: ApplyProgressPresentation {
        ApplyProgressPresentation.make(from: viewModel.state)
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
        .applySheetPresentationCompat(
            prefersLarge: mode == .review,
            prefersTall: mode == .progress || mode == .failed
        )
        .interactiveDismissDisabled(mode == .progress || isStartingSelectedUpdates)
        .onAppear {
            syncSelectionFromAvailableUpdates()
        }
        #if os(macOS)
        .frame(
            minWidth: 460,
            idealWidth: 500,
            maxWidth: 560,
            minHeight: mode == .progress ? 420 : (mode == .review ? 420 : 260),
            idealHeight: mode == .progress ? 500 : (mode == .review ? 500 : 320),
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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sheetHeader
                    progressField
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
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
                    progressField
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

    private var progressField: some View {
        ApplyProgressField(presentation: presentation)
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
}
