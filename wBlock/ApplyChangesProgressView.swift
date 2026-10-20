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

    // Updates start selected, so track what the user unticks. Seeding a selected
    // set on appear left the list unticked for a frame, and unticked entirely
    // when the review replaced another mode in the same sheet.
    @State private var deselectedFilters: Set<UUID> = []
    @State private var deselectedScripts: Set<UUID> = []
    @State private var isStartingSelectedUpdates = false
    @State private var showingLogs = false
    @State private var measuredHeights: [ApplySheetPart: CGFloat] = [:]

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
        selectedFilterUpdates.count + selectedScriptUpdates.count
    }

    private var selectedFilterUpdates: [FilterList] {
        filterManager.availableUpdates.filter { !deselectedFilters.contains($0.id) }
    }

    private var selectedScriptUpdates: [UserScript] {
        filterManager.availableScriptUpdates.filter { !deselectedScripts.contains($0.id) }
    }

    private var totalAvailableUpdateCount: Int {
        filterManager.availableUpdates.count + filterManager.availableScriptUpdates.count
    }

    private var isDismissDisabled: Bool {
        mode == .progress || (mode == .review && isStartingSelectedUpdates)
    }

    private var fillsAvailableHeight: Bool {
        mode == .review || mode == .failed
    }

    private var fittedHeight: CGFloat? {
        guard !fillsAvailableHeight else { return nil }
        let part: ApplySheetPart = mode == .progress ? .progress : .result
        let contentHeight = measuredHeights[part] ?? (mode == .progress ? 480 : 240)
        let toolbarHeight = mode == .progress ? (measuredHeights[.toolbar] ?? 48) : 0
        return ceil((measuredHeights[.header] ?? 52) + contentHeight + toolbarHeight)
    }

    var body: some View {
        SheetContainer(fill: sheetFill) {
            SheetHeader(title: headerTitle, isLoading: isDismissDisabled) {
                isPresented = false
            }
            .measureApplySheetPart(.header)

            content
                .frame(maxWidth: .infinity, maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .top)

            if mode == .review {
                reviewToolbar
            } else if mode == .progress {
                progressToolbar.measureApplySheetPart(.toolbar)
            }
            #if os(iOS)
            // Before iOS 18 an iPad form sheet ignores the fitted detent and keeps
            // its fixed size, so pin the content to the top instead of centering it.
            Spacer(minLength: 0)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .top)
        .applySheetPresentationCompat(
            prefersLarge: fillsAvailableHeight,
            contentHeight: fittedHeight,
            fitsHorizontally: false
        )
        .onPreferenceChange(ApplySheetHeightsKey.self) { measuredHeights = $0 }
        .interactiveDismissDisabled(isDismissDisabled)
        .sheet(isPresented: $showingLogs) {
            #if os(iOS)
            LogsView { showingLogs = false }
            #else
            SheetContainer {
                SheetHeader(title: "Logs") { showingLogs = false }
                LogsView()
            }
            .frame(width: 700, height: 500)
            #endif
        }
        .onChangeCompat(of: mode) { _, newMode in
            if newMode == .review {
                deselectedFilters = []
                deselectedScripts = []
            }
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
        .background(FinishedSheetDismissal(isActive: mode == .result) { isPresented = false })
        #endif
        #if os(macOS)
        .frame(
            minWidth: mode == .result ? 460 : 560,
            idealWidth: mode == .result ? 460 : 560,
            maxWidth: mode == .result ? 460 : 560,
            minHeight: fillsAvailableHeight ? 320 : nil,
            idealHeight: fillsAvailableHeight ? 560 : nil,
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
            fittedContent { progressField }
        case .result:
            fittedContent {
                VStack(alignment: .leading, spacing: 16) {
                    if let summary = viewModel.state.summary {
                        summaryCard(summary)
                    }
                }
            }
        case .failed:
            fittedContent {
                VStack(alignment: .leading, spacing: 16) {
                    failureCard
                    ApplyProgressField(presentation: presentation, showsOnlyFailedPhase: true)
                }
            }
        }
    }

    @ViewBuilder
    private func fittedContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let measured = content().padding(20)
            .measureApplySheetPart(mode == .progress ? .progress : .result)
        if #available(iOS 16.0, macOS 13.0, *) {
            ViewThatFits(in: .vertical) {
                measured.fixedSize(horizontal: false, vertical: true)
                ScrollView { measured }
            }
        } else if mode == .result {
            measured
        } else {
            ScrollView { measured }.frame(height: 480)
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

            Form {
                ForEach(visibleCategories, id: \.self) { category in
                    Section {
                        ForEach(filtersByCategory[category] ?? []) { filter in
                            updateToggle(
                                filter.localizedDisplayName,
                                subtitle: filter.localizedDisplayDescription,
                                isOn: !deselectedFilters.contains(filter.id)
                            ) { toggleFilter(filter) }
                        }
                        if category == .scripts {
                            ForEach(filterManager.availableScriptUpdates) { script in
                                updateToggle(
                                    script.localizedDisplayName,
                                    subtitle: script.localizedDisplayDescription,
                                    isOn: !deselectedScripts.contains(script.id)
                                ) { toggleScript(script) }
                            }
                        }
                    } header: {
                        categoryHeader(category)
                    }
                }
            }
            .groupedFormStyleCompat()
        }
    }

    /// One update per native toggle: a checkbox on macOS, a switch on iOS.
    /// Type matches the filter rows on the main list.
    private func updateToggle(_ title: String, subtitle: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in toggle() })) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .fontWeight(.medium)
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        #if os(macOS)
        .toggleStyle(.checkbox)
        #endif
    }

    private var progressToolbar: some View {
        SheetBottomToolbar {
            #if os(macOS)
            Spacer()
            #endif
            // An auto-update run can't be stopped from here; Close only hides it.
            Button {
                if filterManager.isApplyInFlight {
                    filterManager.cancelInFlightApply()
                } else {
                    filterManager.showingApplyProgressSheet = false
                }
            } label: {
                Text(filterManager.isApplyInFlight ? String(localized: "Cancel") : String(localized: "Close"))
                    .sheetActionWidth()
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private var reviewToolbar: some View {
        SheetBottomToolbar {
            #if os(macOS)
            Spacer()
            #endif
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
                .sheetActionWidth()
            }
            .updateAndApplyButtonStyle()
            .disabled(selectedUpdateCount == 0 || isStartingSelectedUpdates)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(String(localized: "Update & Apply"))
        }
    }

    private func categoryHeader(_ category: FilterListCategory) -> some View {
        let selected = isCategorySelected(category)
        return HStack {
            Text(category.localizedName)
            Spacer()
            Button(selected ? "Deselect All" : "Select All") {
                setCategory(category, selected: !selected)
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .textCase(nil)
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

            if !viewModel.state.resultWarning.isEmpty || !filterManager.failedReloadTargets.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if !viewModel.state.resultWarning.isEmpty {
                        warningLink(viewModel.state.resultWarning)
                    }

                    if !filterManager.failedReloadTargets.isEmpty {
                        Spacer(minLength: 0)
                        Button {
                            filterManager.retryFailedReloads()
                        } label: {
                            Label(String(localized: "Retry"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(filterManager.isLoading)
                        .accessibilityLabel(
                            String.localizedStringWithFormat(
                                NSLocalizedString(
                                    "Retry %d failed extension(s)",
                                    comment: "Summary button that reloads only the blockers that failed"
                                ),
                                filterManager.failedReloadTargets.count
                            )
                        )
                    }
                }
            }

            if viewModel.state.scriptsFailedCount > 0 {
                warningLink(
                    String.localizedStringWithFormat(
                        NSLocalizedString(
                            "%d script update(s) failed",
                            comment: "Apply changes script failure caption"
                        ),
                        viewModel.state.scriptsFailedCount
                    )
                )
            }

        }
    }

    private func warningLink(_ message: String) -> some View {
        Button { showingLogs = true } label: {
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right")
            }
            .font(.caption)
            .foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
        .accessibilityHint("View Logs")
    }

    private var failureCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .imageScale(.large)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Apply Failed"))
                    .font(.title3.weight(.semibold))

                Button { showingLogs = true } label: {
                    Text(failureText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("View Logs")
            }

            Spacer(minLength: 12)

            Button {
                filterManager.forceApplyChanges(checkForUpdates: true)
            } label: {
                Label(String(localized: "Try Again"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(filterManager.isLoading || filterManager.isApplyInFlight)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func toggleFilter(_ filter: FilterList) {
        if deselectedFilters.remove(filter.id) == nil {
            deselectedFilters.insert(filter.id)
        }
    }

    private func toggleScript(_ script: UserScript) {
        if deselectedScripts.remove(script.id) == nil {
            deselectedScripts.insert(script.id)
        }
    }

    private func isCategorySelected(_ category: FilterListCategory) -> Bool {
        if category == .scripts {
            return !filterManager.availableScriptUpdates.isEmpty
                && filterManager.availableScriptUpdates.allSatisfy { !deselectedScripts.contains($0.id) }
        }
        guard let filters = filtersByCategory[category], !filters.isEmpty else { return false }
        return filters.allSatisfy { !deselectedFilters.contains($0.id) }
    }

    private func setCategory(_ category: FilterListCategory, selected: Bool) {
        if category == .scripts {
            deselectedScripts = selected ? [] : Set(filterManager.availableScriptUpdates.map(\.id))
            return
        }
        let ids = Set((filtersByCategory[category] ?? []).map(\.id))
        if selected {
            deselectedFilters.subtract(ids)
        } else {
            deselectedFilters.formUnion(ids)
        }
    }

    private func startSelectedUpdates() async {
        guard !isStartingSelectedUpdates else { return }
        isStartingSelectedUpdates = true
        defer { isStartingSelectedUpdates = false }

        await filterManager.downloadAndApplySelectedUpdates(
            filters: selectedFilterUpdates,
            scripts: selectedScriptUpdates
        )
    }

    // MARK: - Copy helpers

    /// Liquid glass shows through on iOS 26. Earlier sheets are plain white,
    /// which hides the white stat cards, so they get the grouped gray canvas.
    private var sheetFill: SheetFill {
        #if os(iOS)
        if #available(iOS 26.0, *) { return .clear }
        return .grouped
        #else
        return .clear
        #endif
    }

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
    /// iOS sheet actions span the sheet; macOS buttons keep their natural width.
    @ViewBuilder
    func sheetActionWidth() -> some View {
        #if os(iOS)
        self.frame(maxWidth: .infinity)
        #else
        self
        #endif
    }

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

private enum ApplySheetPart: Hashable {
    case header, progress, result, toolbar
}

private struct ApplySheetHeightsKey: PreferenceKey {
    static var defaultValue: [ApplySheetPart: CGFloat] { [:] }
    static func reduce(value: inout [ApplySheetPart: CGFloat], nextValue: () -> [ApplySheetPart: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

private extension View {
    func measureApplySheetPart(_ part: ApplySheetPart) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: ApplySheetHeightsKey.self, value: [part: ceil(proxy.size.height)])
            }
        }
    }
}

#if os(macOS)
/// Once an apply has finished, Return, Space, or a click outside the sheet
/// closes it, the way a tap outside closes it on iOS.
private struct FinishedSheetDismissal: NSViewRepresentable {
    let isActive: Bool
    let dismiss: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.isActive = isActive
        view.dismiss = dismiss
    }

    final class MonitorView: NSView {
        var isActive = false
        var dismiss: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
                guard let self, self.isActive, let sheet = self.window else { return event }
                switch event.type {
                case .keyDown where [36, 49, 76].contains(event.keyCode)
                    && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty:
                    self.dismiss()
                    return nil
                case .leftMouseDown where event.window !== sheet:
                    self.dismiss()
                    return nil
                default:
                    return event
                }
            }
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }
    }
}
#endif
