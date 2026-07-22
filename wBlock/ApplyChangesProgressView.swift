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
    @State private var selectedCategories: Set<FilterListCategory> = []
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
        SheetContainer {
            VStack(spacing: 0) {
                SheetHeader(
                    title: headerTitle,
                    isLoading: mode == .progress || isStartingSelectedUpdates
                ) {
                    isPresented = false
                }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if mode == .review {
                    reviewToolbar
                } else if mode == .result || mode == .failed {
                    resultToolbar
                }
            }
        }
        .onAppear {
            syncSelectionFromAvailableUpdates()
        }
        .onChangeCompat(of: filterManager.availableUpdates.map(\.id)) { _, _ in
            if mode == .review {
                syncSelectionFromAvailableUpdates()
            }
        }
        .onChangeCompat(of: filterManager.availableScriptUpdates.map(\.id)) { _, _ in
            if mode == .review {
                syncSelectionFromAvailableUpdates()
            }
        }
        #if os(macOS)
        .frame(
            minWidth: 460,
            idealWidth: 500,
            maxWidth: 560,
            minHeight: mode == .review ? 420 : 360,
            idealHeight: mode == .review ? 500 : 420,
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
                VStack(alignment: .leading, spacing: 16) {
                    progressOverviewCard
                    phaseCard
                }
                .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        case .result:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let summary = viewModel.state.summary {
                        resultHeaderCard
                        summaryCard(summary)
                        if !summary.ruleCountsByBlocker.isEmpty {
                            extensionBreakdownCard(summary)
                        }
                        phaseCard
                    }
                }
                .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        case .failed:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    failureCard
                    phaseCard
                }
                .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Review

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
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

                Text(
                    String(
                        localized: "Choose which filters and scripts to download, then apply changes."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SheetDesign.contentHorizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 12)

            List {
                ForEach(visibleCategories, id: \.self) { category in
                    Section {
                        if let filters = filtersByCategory[category] {
                            ForEach(filters, id: \.id) { filter in
                                selectionRow(
                                    title: filter.localizedDisplayName,
                                    subtitle: filter.localizedDisplayDescription,
                                    isSelected: selectedFilters.contains(filter.id)
                                ) {
                                    toggleFilter(filter, in: category)
                                }
                            }
                        }

                        if category == .scripts {
                            ForEach(filterManager.availableScriptUpdates, id: \.id) { script in
                                selectionRow(
                                    title: script.localizedDisplayName,
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
                "",
                isOn: Binding(
                    get: { selectedCategories.contains(category) },
                    set: { isSelected in
                        setCategory(category, selected: isSelected)
                    }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }

    private func selectionRow(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .imageScale(.medium)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var reviewToolbar: some View {
        SheetBottomToolbar {
            Button(String(localized: "Cancel")) {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

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
            .primaryActionButtonStyle()
            .disabled(selectedUpdateCount == 0 || isStartingSelectedUpdates)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Progress / Result

    private var progressOverviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(activePhaseTitle)
                    .font(.title3.weight(.semibold))

                if !viewModel.state.statusMessage.isEmpty {
                    Text(viewModel.state.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ProgressView(value: viewModel.state.progress, total: 1)
                .progressViewStyle(.linear)

            HStack {
                Text("\(viewModel.state.progressPercentage)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    String.localizedStringWithFormat(
                        NSLocalizedString(
                            "%d update(s) found",
                            comment: "Apply changes updates found caption"
                        ),
                        viewModel.state.updatesFound
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    title: String(localized: "Extensions"),
                    value: processedText,
                    icon: "puzzlepiece.extension",
                    pillColor: .blue,
                    valueColor: .primary
                )
                StatCard(
                    title: String(localized: "Scripts"),
                    value: scriptsProgressText,
                    icon: "bolt.horizontal.circle",
                    pillColor: .green,
                    valueColor: .primary
                )
            }
        }
    }

    private var resultHeaderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.large)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Applied"))
                        .font(.title3.weight(.semibold))
                    Text(resultSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .imageScale(.large)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Apply Failed"))
                        .font(.title3.weight(.semibold))
                    Text(
                        viewModel.state.failureMessage.isEmpty
                            ? String(localized: "Something went wrong while applying changes.")
                            : viewModel.state.failureMessage
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
    }

    private var phaseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Progress"))
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(viewModel.state.phases.indices, id: \.self) { index in
                    let step = viewModel.state.phases[index]
                    PhaseRow(
                        step: step,
                        detail: detail(for: step),
                        subProgress: subProgress(for: step.phase, status: step.status)
                    )
                    if index < viewModel.state.phases.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(phaseCardBackground)
            )
        }
    }

    private func summaryCard(_ summary: ApplyChangesSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    title: String(localized: "Safari Rules"),
                    value: summary.safariRules.formatted(),
                    icon: "shield.lefthalf.filled",
                    pillColor: .blue,
                    valueColor: .primary
                )
                StatCard(
                    title: String(localized: "Source Rules"),
                    value: summary.sourceRules.formatted(),
                    icon: "doc.text",
                    pillColor: .orange,
                    valueColor: .primary
                )
                StatCard(
                    title: String(localized: "Conversion"),
                    value: summary.conversionTime,
                    icon: "clock",
                    pillColor: .green,
                    valueColor: .primary
                )
                StatCard(
                    title: String(localized: "Reload"),
                    value: summary.reloadTime,
                    icon: "arrow.clockwise",
                    pillColor: .purple,
                    valueColor: .primary
                )
            }

            if !summary.blockersApproachingLimit.isEmpty {
                Label(
                    String.localizedStringWithFormat(
                        NSLocalizedString(
                            "Near Safari limit: %@",
                            comment: "Apply changes near-limit warning"
                        ),
                        summary.blockersApproachingLimit.sorted().joined(separator: ", ")
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private func extensionBreakdownCard(_ summary: ApplyChangesSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Extensions"))
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(summary.ruleCountsByBlocker.keys.sorted(), id: \.self) { name in
                    let count = summary.ruleCountsByBlocker[name] ?? 0
                    let nearLimit = summary.blockersApproachingLimit.contains(name)

                    HStack {
                        Label(name, systemImage: "puzzlepiece.extension")
                            .font(.subheadline)
                        Spacer()
                        Text(count.formatted())
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(nearLimit ? .orange : .secondary)
                        if nearLimit {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    if name != summary.ruleCountsByBlocker.keys.sorted().last {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(phaseCardBackground)
            )
        }
    }

    private var resultToolbar: some View {
        SheetBottomToolbar {
            Spacer()
            Button(String(localized: "Done")) {
                isPresented = false
            }
            .primaryActionButtonStyle()
            .keyboardShortcut(.defaultAction)
            Spacer()
        }
    }

    // MARK: - Actions

    private func syncSelectionFromAvailableUpdates() {
        selectedFilters = Set(filterManager.availableUpdates.map(\.id))
        selectedScripts = Set(filterManager.availableScriptUpdates.map(\.id))
        var categories = Set(filterManager.availableUpdates.map(\.category))
        if !filterManager.availableScriptUpdates.isEmpty {
            categories.insert(.scripts)
        }
        selectedCategories = categories
    }

    private func toggleFilter(_ filter: FilterList, in category: FilterListCategory) {
        if selectedFilters.contains(filter.id) {
            selectedFilters.remove(filter.id)
            let remaining = (filtersByCategory[category] ?? []).filter { selectedFilters.contains($0.id) }
            if remaining.isEmpty {
                selectedCategories.remove(category)
            }
        } else {
            selectedFilters.insert(filter.id)
            selectedCategories.insert(category)
        }
    }

    private func toggleScript(_ script: UserScript) {
        if selectedScripts.contains(script.id) {
            selectedScripts.remove(script.id)
            if selectedScripts.isEmpty {
                selectedCategories.remove(.scripts)
            }
        } else {
            selectedScripts.insert(script.id)
            selectedCategories.insert(.scripts)
        }
    }

    private func setCategory(_ category: FilterListCategory, selected: Bool) {
        if selected {
            selectedCategories.insert(category)
            if category == .scripts {
                selectedScripts = Set(filterManager.availableScriptUpdates.map(\.id))
            } else if let filters = filtersByCategory[category] {
                for filter in filters {
                    selectedFilters.insert(filter.id)
                }
            }
        } else {
            selectedCategories.remove(category)
            if category == .scripts {
                selectedScripts.removeAll()
            } else if let filters = filtersByCategory[category] {
                for filter in filters {
                    selectedFilters.remove(filter.id)
                }
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
        case .progress:
            return String(localized: "Apply Changes")
        case .result:
            return String(localized: "Apply Changes")
        case .failed:
            return String(localized: "Apply Changes")
        }
    }

    private var activePhaseTitle: String {
        if let active = viewModel.state.phases.first(where: { $0.status == .active }) {
            return active.phase.title
        }
        return String(localized: "Apply Changes")
    }

    private var resultSubtitle: String {
        if !viewModel.state.statusMessage.isEmpty {
            return viewModel.state.statusMessage
        }
        return String(localized: "Filters and scripts applied successfully.")
    }

    private var processedText: String {
        let total = viewModel.state.totalCount
        if total > 0 {
            return "\(total)"
        }
        return "—"
    }

    private var scriptsProgressText: String {
        let updated = viewModel.state.scriptsUpdatedCount
        let failed = viewModel.state.scriptsFailedCount
        if updated == 0 && failed == 0 {
            return "—"
        }
        if failed > 0 {
            return "\(updated)/\(updated + failed)"
        }
        return "\(updated)"
    }

    private var phaseCardBackground: Color {
        #if os(iOS)
        Color(UIColor.secondarySystemGroupedBackground)
        #else
        Color.primary.opacity(0.04)
        #endif
    }

    private func detail(for step: ApplyChangesPhaseProgress) -> String? {
        switch step.phase {
        case .updating:
            if step.status == .complete {
                let count = viewModel.state.updatesFound
                if count > 0 {
                    return localizedCountDetail("Downloaded %d updates", count: count)
                }
                return String(localized: "No updates available")
            }
            return nil
        case .scripts:
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
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                statusLeading
                    .frame(width: 18, height: 18)

                Image(systemName: step.phase.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(iconColor)
                    .frame(width: 18)

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
                .padding(.leading, 48)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var iconColor: Color {
        switch step.status {
        case .pending: return .secondary
        case .active: return .accentColor
        case .complete: return .green
        case .failed: return .red
        }
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
