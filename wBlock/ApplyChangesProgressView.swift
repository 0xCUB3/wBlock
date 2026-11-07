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
    // The sheet is dismissed when an apply starts, so it keeps drawing the last
    // non-progress mode it showed instead of the live one. Otherwise the sheet
    // flashes its contents for a frame while it slides away.
    @State private var displayedMode: ApplyChangesSheetMode

    init(filterManager: AppFilterManager, viewModel: ApplyChangesViewModel, isPresented: Binding<Bool>) {
        _filterManager = ObservedObject(wrappedValue: filterManager)
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _isPresented = isPresented
        _displayedMode = State(initialValue: viewModel.state.mode)
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
        displayedMode == .review && isStartingSelectedUpdates
    }

    private var fillsAvailableHeight: Bool {
        displayedMode == .review
    }

    private var fittedHeight: CGFloat? {
        guard !fillsAvailableHeight else { return nil }
        let contentHeight = measuredHeights[.content] ?? 240
        return ceil((measuredHeights[.header] ?? 52) + contentHeight)
    }

    var body: some View {
        SheetContainer(fill: sheetFill) {
            SheetHeader(title: headerTitle, isLoading: isDismissDisabled) {
                isPresented = false
            }
            .measureApplySheetPart(.header)

            content
                .frame(maxWidth: .infinity, maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .top)

            if displayedMode == .review {
                reviewToolbar
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
        .onChangeCompat(of: viewModel.state.mode) { _, newMode in
            if newMode != .progress { displayedMode = newMode }
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
        .background(FinishedResultDismissal(isActive: displayedMode == .result) { isPresented = false })
        #endif
        #if os(macOS)
        .frame(
            minWidth: displayedMode == .review ? 560 : 460,
            idealWidth: displayedMode == .review ? 560 : 460,
            maxWidth: displayedMode == .review ? 560 : 460,
            minHeight: fillsAvailableHeight ? 320 : nil,
            idealHeight: fillsAvailableHeight ? 560 : nil,
            maxHeight: 640
        )
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch displayedMode {
        case .review:
            reviewContent
        case .progress:
            EmptyView()
        case .result:
            fittedContent { resultWarnings }
        case .failed:
            fittedContent { failureCard }
        }
    }

    @ViewBuilder
    private func fittedContent<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let measured = content().padding(20).measureApplySheetPart(.content)
        if #available(iOS 16.0, macOS 13.0, *) {
            ViewThatFits(in: .vertical) {
                measured.fixedSize(horizontal: false, vertical: true)
                ScrollView { measured }
            }
        } else {
            measured
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
    private func updateToggle(_ title: String, subtitle: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        SelectableRow(title: Text(verbatim: title), subtitle: subtitle, isSelected: isOn, action: toggle)
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

    // MARK: - Result

    /// Shown only when the run left something to fix; a clean run closes itself.
    private var resultWarnings: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 12) {
            failureSummary
            ForEach(viewModel.state.limitFixes) { fix in
                limitFixRow(fix)
            }
        }
    }

    /// One list from a blocker over Safari's limit. Turning it off applies again.
    private func limitFixRow(_ fix: ApplyLimitFix) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fix.name)
                    .font(.subheadline.weight(.medium))
                if let size = fix.size {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let detail = fix.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(fix.fits ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if viewModel.state.limitFixesMeasuring {
                    ProgressView().controlSize(.mini)
                }
            }
            Spacer(minLength: 12)
            Button(String(localized: "Turn Off")) {
                filterManager.setFilterListSelection(id: fix.id, selected: false)
                filterManager.forceApplyChanges()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(filterManager.isLoading || filterManager.isApplyInFlight)
            .accessibilityLabel(String.localizedStringWithFormat(
                NSLocalizedString("Turn off %@ and apply", comment: "Over-limit fix button"), fix.name
            ))
        }
    }

    private var failureSummary: some View {
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
    /// The review is a grouped form, so its header and button share the
    /// form's gray instead of sitting on white bands above and below it.
    private var sheetFill: SheetFill {
        #if os(iOS)
        if #available(iOS 26.0, *), displayedMode != .review { return .clear }
        return .grouped
        #else
        return .clear
        #endif
    }

    private var headerTitle: String {
        switch displayedMode {
        case .review:
            return "Available Updates"
        default:
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
    case header, content
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
/// Return, Space, or a click outside the view it backs closes a finished
/// apply's sheet or banner, the way a tap outside closes them on iOS.
struct FinishedResultDismissal: NSViewRepresentable {
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
                guard let self, self.isActive, let window = self.window else { return event }
                switch event.type {
                case .keyDown where event.window === window && [36, 49, 76].contains(event.keyCode)
                    && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
                    && !(window.firstResponder is NSText):
                    self.dismiss()
                    return nil
                case .leftMouseDown where event.window !== window
                    || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)):
                    self.dismiss()
                    // A click on a sheet's parent window would only beep.
                    return event.window === window.sheetParent ? nil : event
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

