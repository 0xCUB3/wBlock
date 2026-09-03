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

    private var isDismissDisabled: Bool {
        mode == .progress || isStartingSelectedUpdates
    }

    var body: some View {
        SheetContainer(fill: .clear) {
            SheetHeader(title: headerTitle, isLoading: isDismissDisabled) {
                isPresented = false
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: mode == .review ? .top : .center)

            if mode == .review {
                reviewToolbar
            } else if mode == .progress {
                progressToolbar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: mode == .review ? .top : .center)
        .applySheetPresentationCompat(prefersLarge: mode == .review)
        .interactiveDismissDisabled(isDismissDisabled)
        .onAppear {
            syncSelectionFromAvailableUpdates()
        }
        #if os(macOS)
        .background {
            // Sheets normally close with Escape; Cmd+W is the reflex users
            // reach for, so let it dismiss the sheet too unless an apply is
            // in flight.
            Button {
                isPresented = false
            } label: {
                Color.clear
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(isDismissDisabled)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        #endif
        #if os(macOS)
        .frame(
            minWidth: 460,
            idealWidth: 500,
            maxWidth: 560,
            minHeight: mode == .result ? nil : 320,
            // Six phase rows with a detail line each, the bar, header, and
            // toolbar need ~540pt; at 360 the last two rows were clipped.
            idealHeight: mode == .result ? nil : 560,
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
                    progressField
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        case .result:
            // The summary is four stat cards and at most two captions; it never
            // needs to scroll, and a scrolling container here stretches the sheet
            // to the fixed macOS ideal height and leaves a blank band underneath.
            VStack(alignment: .leading, spacing: 16) {
                if let summary = viewModel.state.summary {
                    summaryCard(summary)
                }
            }
            .padding(20)
        case .failed:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    failureCard
                    progressField

                    Button {
                        filterManager.forceApplyChanges()
                    } label: {
                        Text(String(localized: "Try Again"))
                            .frame(maxWidth: .infinity)
                    }
                    .primaryActionButtonStyle()
                    .disabled(filterManager.isLoading || filterManager.isApplyInFlight)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(20)
            }
        }
    }

    // MARK: - Review

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(visibleCategories, id: \.self) { category in
                        reviewSection(category)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func reviewSection(_ category: FilterListCategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            categoryHeader(category)

            VStack(spacing: 0) {
                if let filters = filtersByCategory[category] {
                    ForEach(Array(filters.enumerated()), id: \.element.id) { index, filter in
                        if index > 0 {
                            Divider().padding(.leading, 44)
                        }
                        SelectableRow(
                            title: Text(filter.localizedDisplayName),
                            subtitle: filter.localizedDisplayDescription,
                            isSelected: selectedFilters.contains(filter.id),
                            style: .groupedRow
                        ) {
                            toggleFilter(filter)
                        }
                    }
                }

                if category == .scripts {
                    ForEach(
                        Array(filterManager.availableScriptUpdates.enumerated()),
                        id: \.element.id
                    ) { index, script in
                        if index > 0 || filtersByCategory[category] != nil {
                            Divider().padding(.leading, 44)
                        }
                        SelectableRow(
                            title: Text(script.localizedDisplayName),
                            subtitle: script.localizedDisplayDescription,
                            isSelected: selectedScripts.contains(script.id),
                            style: .groupedRow
                        ) {
                            toggleScript(script)
                        }
                    }
                }
            }
            .liquidGlassCompat(cornerRadius: 12, material: .regularMaterial)
        }
    }

    private var progressToolbar: some View {
        SheetBottomToolbar {
            Button {
                filterManager.cancelInFlightApply()
            } label: {
                Text(String(localized: "Cancel"))
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private var reviewToolbar: some View {
        SheetBottomToolbar {
            Button {
                Task { await startSelectedUpdates() }
            } label: {
                ZStack {
                    Text(String(localized: "Update & Apply"))
                        .opacity(isStartingSelectedUpdates ? 0 : 1)
                    if isStartingSelectedUpdates {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .updateAndApplyButtonStyle()
            .disabled(selectedUpdateCount == 0 || isStartingSelectedUpdates)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(String(localized: "Update & Apply"))
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
        .padding(.horizontal, 4)
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
            return "Available Updates"
        case .progress, .result, .failed:
            return "Apply Changes"
        }
    }

    private var failureText: String {
        if viewModel.state.failureMessage.isEmpty {
            return String(localized: "Something went wrong while applying changes.")
        }
        return viewModel.state.failureMessage
    }
}

private extension View {
    @ViewBuilder
    func updateAndApplyButtonStyle() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
                .controlSize(.large)
        } else {
            self.primaryActionButtonStyle()
        }
        #else
        self.primaryActionButtonStyle()
        #endif
    }
}
