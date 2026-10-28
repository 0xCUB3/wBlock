//
//  ContentView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import Combine
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import wBlockCoreService

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

struct ContentView: View {
    @ObservedObject var filterManager: AppFilterManager
    @StateObject private var userScriptManager = UserScriptManager.shared
    @StateObject private var dataManager = ProtobufDataManager.shared
    @State private var showingAddFilterSheet = false
    @State private var downloadingFilterIDs: Set<UUID> = []
    /// Filters with a cached copy on disk. Each row used to stat the app group
    /// on every body evaluation, which multiplied by 84 rows on every progress
    /// tick; now the set is rebuilt only when the list or an apply run changes.
    @State private var downloadedFilterIDs: Set<UUID> = []
    @State private var showingFilterDownloadError = false
    @AppStorage(ListDisplayOrder.filtersEnabledOnlyKey) private var showOnlyEnabledLists = false
    @AppStorage(ListDisplayOrder.filtersKey) private var filterDisplayOrder = Data()
    @State private var filterSearchText = ""
    @State private var showFilterSearch = false
    @State private var editingCustomFilter: FilterList?
    @State private var selectedFilterInfo: FilterList?
    @State private var selectedFilterSettings: FilterList?
    @State private var selectedFilterRules: FilterList?
    @State private var selectedFilterFallbacks: FilterList?
    @State private var selectedCategoryInfo: FilterListCategory?
    @State private var isForeignFiltersExpanded = ProtobufDataManager.shared.isForeignFiltersExpanded
    @State private var showingCapacityPopover = false
    // Only AppTabView observes selection. A tab click must not invalidate every row.
    @State private var tabSelection = AppTabSelection()
    private var selectedTab: Int {
        get { tabSelection.value }
        nonmutating set { tabSelection.value = newValue }
    }

    private var shouldExpandForeignFilters: Bool {
        showOnlyEnabledLists || isForeignFiltersExpanded
    }
    // Prepared off the main actor: every progress publish re-renders this view,
    // and sorting the catalog there stalled older iPads until the watchdog fired (#860).
    @State private var filterPresentation = FilterListPresentation()
    @Environment(\.locale) private var locale

    private var filterPresentationInput: FilterListPresentation.Input {
        .init(filters: filterManager.filterLists, order: filterDisplayOrder,
              searchText: filterSearchText, enabledOnly: showOnlyEnabledLists,
              localeIdentifier: locale.identifier, downloadedIDs: downloadedFilterIDs,
              lastModified: dataManager.filterLastModified)
    }
    @State private var pendingEssentialFilter: FilterList?
    @State private var pendingRiskyEnable: RiskyFilterEnable?
    /// Monotonic tokens handed to the Userscripts tab so a ⌘⇧N or ⌘L that
    /// arrives before that tab has been built is still honored on appear.
    @State private var addUserScriptRequest = 0
    @State private var userScriptSearchRequest = 0
    @State private var showingLogs = false
    @Environment(\.scenePhase) var scenePhase

    private var enabledListsCount: Int {
        filterManager.filterLists.filter { $0.isSelected }.count
    }

    /// Total source rules from selected filters (handles nil gracefully)
    private var sourceRulesCount: Int {
        filterManager.filterLists
            .filter { $0.isSelected }
            .reduce(0) { $0 + ($1.sourceRuleCount ?? 0) }
    }

    /// Safari rules applied to content blockers (the count that matters for limits)
    private var appliedSafariRulesCount: Int {
        filterManager.lastRuleCount
    }

    /// Whether filters have been applied at least once
    private var hasAppliedFilters: Bool {
        filterManager.lastRuleCount > 0
    }

    private var hasPendingChanges: Bool {
        filterManager.hasUnappliedChanges
    }

    private var shouldShowRuleLimitIndicator: Bool {
        hasAppliedFilters && appliedSafariRulesCount >= filterManager.safariRuleCapacity
    }

    private var applyChangesSymbolName: String {
        "arrow.triangle.2.circlepath"
    }

    private var categorizedFilters: [(category: FilterListCategory, filters: [FilterList])] {
        filterPresentation.sections.map { ($0.category, $0.filters) }
    }

    /// Invisible zero-size buttons that surface hardware-keyboard shortcuts.
    /// SwiftUI keeps delivering key events to them even though they render
    /// nothing, so the same shortcuts work on macOS and on iOS with an
    /// attached hardware keyboard.
    private var keyboardShortcutHandlers: some View {
        Group {
            // macOS and iPadOS get these from the menu bar (wBlockApp.commands),
            // so the hidden buttons only exist for iPhone hardware keyboards.
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
            Button {
                guard !filterManager.isLoading,
                    !filterManager.showingApplyProgressSheet
                else { return }
                applyPendingChanges()
            } label: {
                Color.clear
            }
            .keyboardShortcut("r", modifiers: .command)

            Button {
                selectedTab = 0
            } label: {
                Color.clear
            }
            .keyboardShortcut("1", modifiers: .command)

            Button {
                selectedTab = 1
            } label: {
                Color.clear
            }
            .keyboardShortcut("2", modifiers: .command)

            Button {
                selectedTab = 2
            } label: {
                Color.clear
            }
            .keyboardShortcut("3", modifiers: .command)

            Button {
                NotificationCenter.default.post(name: .wBlockAddFilterListRequest, object: nil)
            } label: {
                Color.clear
            }
            .keyboardShortcut("n", modifiers: .command)

            Button {
                NotificationCenter.default.post(name: .wBlockAddUserScriptRequest, object: nil)
            } label: {
                Color.clear
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button {
                NotificationCenter.default.post(name: .wBlockSearchRequest, object: nil)
            } label: {
                Color.clear
            }
            .keyboardShortcut("l", modifiers: .command)

            Button {
                NotificationCenter.default.post(name: .wBlockCheckFilterUpdatesRequest, object: nil)
            } label: {
                Color.clear
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Button {
                NotificationCenter.default.post(name: .wBlockCheckScriptUpdatesRequest, object: nil)
            } label: {
                Color.clear
            }
            .keyboardShortcut("r", modifiers: [.command, .option, .shift])
            }
            #endif
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    var body: some View {
        AppTabView(selection: tabSelection, filters: filtersView,
                   userscripts: userscriptsView, settings: settingsView)
        .background(keyboardShortcutHandlers)
        .keyboardScrollingCompat()
        .task(id: filterPresentationInput) {
            let input = filterPresentationInput
            if let prepared = try? await FilterListPresentation.prepare(input),
               !Task.isCancelled, input == filterPresentationInput {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { filterPresentation = prepared }
            }
        }
        .modifier(
            ContentModifiers(
                filterManager: filterManager,
                userScriptManager: userScriptManager,
                dataManager: dataManager,
                showingAddFilterSheet: $showingAddFilterSheet,
                scenePhase: scenePhase
            ))
        .sheet(item: $editingCustomFilter) { filter in
            EditCustomFilterView(filterManager: filterManager, filter: filter)
        }
        .infoPresentation(item: $selectedFilterInfo, content: filterInfoContent)
        .infoPresentation(item: $selectedFilterSettings) { filter in
            FilterSettingsView(filter: filter, filterManager: filterManager)
                .infoSheetPresentationCompat()
        }
        .infoPresentation(item: $selectedFilterFallbacks) { filter in
            FilterFallbacksView(filter: filter, urls: FilterListURLMirror.fallbackURLs(for: filter.url))
                .infoSheetPresentationCompat()
        }
        .sheet(item: $selectedFilterRules) { filter in
            if filter.isInlineUserList {
                EditUserListView(filterManager: filterManager, filter: filter)
            } else {
                FilterRulesView(filter: filter, filterManager: filterManager)
            }
        }
        .infoPresentation(item: $selectedCategoryInfo, content: filterCategoryInfoContent)
        .onReceive(tabSelection.$value.removeDuplicates().dropFirst()) { _ in
            selectedFilterInfo = nil
            selectedFilterSettings = nil
            selectedFilterFallbacks = nil
            selectedCategoryInfo = nil
            filterSearchText = ""
            showFilterSearch = false
        }
        .onAppear { refreshDownloadedFilterIDs() }
        .onChangeCompat(of: filterManager.filterLists.map(\.id)) { _, _ in
            refreshDownloadedFilterIDs()
        }
        .onChangeCompat(of: filterManager.isLoading) { _, isLoading in
            if !isLoading { refreshDownloadedFilterIDs() }
        }
        .onChangeCompat(of: filterManager.downloadedFilterRevision) { _, _ in
            refreshDownloadedFilterIDs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wBlockAddFilterListRequest)) { _ in
            selectedTab = 0
            showingAddFilterSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .wBlockAddUserScriptRequest)) { _ in
            selectedTab = 1
            addUserScriptRequest += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .wBlockSearchRequest)) { _ in
            if selectedTab == 1 {
                userScriptSearchRequest += 1
            } else {
                selectedTab = 0
                showFilterSearch = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wBlockCheckFilterUpdatesRequest)) { _ in
            checkForUpdates(scope: .filters)
        }
        .onReceive(NotificationCenter.default.publisher(for: .wBlockCheckScriptUpdatesRequest)) { _ in
            checkForUpdates(scope: .scripts)
        }
        .onReceive(NotificationCenter.default.publisher(for: .wBlockSelectTabRequest)) { note in
            if let tab = note.object as? Int { selectedTab = tab }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wBlockUpdateRequest)) { _ in
            guard !filterManager.isLoading, !filterManager.showingApplyProgressSheet else { return }
            applyPendingChanges()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wBlockToggleEnabledOnlyRequest)) { _ in
            if selectedTab == 0 { showOnlyEnabledLists.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wBlockShowLogsRequest)) { _ in
            showingLogs = true
        }
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
        .alert("Error", isPresented: $showingFilterDownloadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Couldn't download this filter list. It was kept as not downloaded.")
        }
        .alert("Disable Essential Filter?", isPresented: Binding(
            get: { pendingEssentialFilter != nil },
            set: { if !$0 { pendingEssentialFilter = nil } }
        ), presenting: pendingEssentialFilter) { filter in
            Button("Cancel", role: .cancel) { pendingEssentialFilter = nil }
            Button("Disable", role: .destructive) {
                filterManager.setFilterListSelection(id: filter.id, selected: false)
                pendingEssentialFilter = nil
            }
        } message: { _ in
            Text("This recommended filter is part of wBlock’s essential protection. Disabling it may reduce blocking coverage.")
        }
        .riskyFilterAlert($pendingRiskyEnable)
        .onChangeCompat(of: dataManager.isForeignFiltersExpanded) { _, newValue in
            guard isForeignFiltersExpanded != newValue else { return }
            isForeignFiltersExpanded = newValue
        }
        .onChangeCompat(of: isForeignFiltersExpanded) { _, newValue in
            guard dataManager.isForeignFiltersExpanded != newValue else { return }
            Task {
                await dataManager.setIsForeignFiltersExpanded(newValue)
            }
        }
    }

    private func applyPendingChanges() {
        guard !filterManager.isLoading else { return }
        filterManager.applyOrCheckForUpdates()
    }

    /// Scoped manual check (#657): only filters or only userscripts, so one
    /// side can be refreshed without touching the other.
    private func checkForUpdates(scope: AppFilterManager.UpdateCheckScope) {
        guard !filterManager.isLoading, !filterManager.showingApplyProgressSheet else { return }
        Task { await filterManager.checkForUpdates(scope: scope, presentation: .blocking) }
    }

    private var applyChangesToolbarButton: some View {
        let isBusy = filterManager.isLoading || filterManager.isAutoUpdateRunning
        // The spinner sits in the round icon's frame. Sizing it to the hidden
        // Apply word stretched the button into an empty pill during a run
        // that started with changes pending, such as the post-upgrade rebuild.
        let showsApply = hasPendingChanges && !isBusy
        return ApplyChangesButton(
            isDisabled: isBusy,
            hasPendingChanges: hasPendingChanges,
            onTap: applyPendingChanges,
            onBusyTap: filterManager.showBackgroundApplyProgress
        ) {
            #if os(iOS)
            ApplyChangesToolbarLabel(
                hasPendingChanges: showsApply,
                symbolName: applyChangesSymbolName
            )
            #else
            if showsApply {
                Text("Apply").fontWeight(.semibold)
            } else {
                Label("Update", systemImage: applyChangesSymbolName)
            }
            #endif
        }
        #if os(macOS)
        // Right-click exposes the apply variants (#651); iOS uses pull-to-refresh
        // on each tab.
        .contextMenu { scopedUpdateMenuItems }
        #endif
    }

    @ViewBuilder
    private var scopedUpdateMenuItems: some View {
        Button("Check for Filter Updates") { checkForUpdates(scope: .filters) }
        Button("Check for Userscript Updates") { checkForUpdates(scope: .scripts) }
        Divider()
        Button("Apply Without Checking for Updates") { filterManager.forceApplyChanges() }
            .disabled(filterManager.isLoading)
        if !filterManager.failedReloadTargets.isEmpty {
            Button {
                filterManager.showingApplyProgressSheet = true
                filterManager.retryFailedReloads()
            } label: {
                Text(
                    String.localizedStringWithFormat(
                        NSLocalizedString("Retry %d failed extension(s)", comment: "Summary button that reloads only the blockers that failed"),
                        filterManager.failedReloadTargets.count
                    )
                )
            }
            .disabled(filterManager.isLoading)
        }
    }

    private var filtersView: some View {
        CompatibleNavigationStack(requiresNavigationView: false) {
            nativeFiltersListView
                .safeAreaInset(edge: .top) {
                    if filterManager.isBlockingPaused {
                        pauseBlockingBanner
                    }
                }
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                // Inside the stack, like Userscripts; iOS ignores toolbar items attached outside it.
                .modifier(filtersToolbar)
        }
        #if os(iOS)
            .searchableCompat(
                text: $filterSearchText,
                isPresented: $showFilterSearch,
                prompt: "Search filters"
            )
        #endif
        #if os(macOS)
            .frame(
                minWidth: 480, idealWidth: 540, maxWidth: .infinity,
                minHeight: 550, idealHeight: 720, maxHeight: .infinity
            )
        #endif
    }

    private var filtersToolbar: some ViewModifier {
        ListActionsToolbar(
            searchText: $filterSearchText,
            focusRequest: $showFilterSearch,
            showEnabledOnly: $showOnlyEnabledLists,
            searchPrompt: "Search filters"
        ) {
            Button {
                showingAddFilterSheet = true
            } label: {
                Label("Add Filter", systemImage: "plus")
            }
            .help("Add Filter")
        } apply: {
            applyChangesToolbarButton
        }
    }

    private var nativeFiltersListView: some View {
        #if os(iOS)
        let sections = categorizedFilters
        return List {
            Section {
                statsCardsView
                    .unifiedTabCardSectionRow()
            }

            ForEach(sections, id: \.category) { item in
                if item.category == .foreign {
                    // Same section chrome as every other category; the header's
                    // chevron collapses the rows instead of a nested DisclosureGroup.
                    ContentListSection { categoryHeader(item.category) } content: {
                        if shouldExpandForeignFilters {
                            filterRows(item.filters)
                        }
                    }
                } else {
                    ContentListSection { categoryHeader(item.category) } content: {
                        filterRows(item.filters)
                    }
                }
            }
        }
        .unifiedTabListStyle()
        .refreshable {
            guard !filterManager.isLoading else { return }
            await filterManager.checkForUpdates(scope: .filters, presentation: .refresh)
        }
        #else
        MacReorderableList(
            sections: macFilterSections,
            header: AnyView(statsCardsView.padding(.vertical, 16)),
            onMove: commitFilterMove
        )
        .scrollingUnderToolbar()
        #endif
    }

    private var userscriptsView: some View {
        CompatibleNavigationStack(requiresNavigationView: false) {
            UserScriptManagerView(
                userScriptManager: userScriptManager,
                tabSelection: tabSelection,
                addRequest: addUserScriptRequest,
                searchRequest: userScriptSearchRequest,
                onRefresh: {
                    guard !filterManager.isLoading else { return }
                    await filterManager.checkForUpdates(scope: .scripts, presentation: .refresh)
                },
                applyButton: AnyView(applyChangesToolbarButton)
            )
                .safeAreaInset(edge: .top) {
                    if filterManager.isBlockingPaused {
                        pauseBlockingBanner
                    }
                }
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }

    private var settingsView: some View {
        SettingsView(filterManager: filterManager)
    }

    @ViewBuilder
    private var pauseBlockingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Pause Blocking")
                    .font(.subheadline.weight(.semibold))
                Text("Pause Blocking is on while any selected component is paused. Resume restores all components.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                Task { await filterManager.setBlockingPaused(false) }
            } label: {
                if filterManager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Resume")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
            .disabled(filterManager.isLoading)
            .accessibilityLabel("Resume Blocking")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
    }

    private var statsCardsView: some View {
        StatsCardsView {
            Button {
                showingCapacityPopover = true
            } label: {
                StatCard(
                    title: {
                        #if os(iOS)
                        return "Safari Rules"
                        #else
                        return (enabledListsCount == 0 || !hasAppliedFilters) ? "Source Rules" : "Safari Rules"
                        #endif
                    }(),
                    value: enabledListsCount == 0
                        ? "0"
                        : (hasAppliedFilters
                            ? appliedSafariRulesCount.formatted()
                            : (sourceRulesCount > 0 ? "~\(sourceRulesCount.formatted())" : "0")),
                    icon: "shield.lefthalf.filled",
                    valueColor: enabledListsCount == 0 ? .secondary : (hasAppliedFilters ? .primary : .secondary),
                    showsDisclosure: true
                )
                .overlay(alignment: .topTrailing) {
                    if shouldShowRuleLimitIndicator {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.trailing, 6)
                            .padding(.top, 4)
                    }
                }
                #if os(iOS)
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
            }
            .buttonStyle(.plain)
            .noFocusRingCompat()
            #if os(macOS)
            .modalPopover(isPresented: $showingCapacityPopover, arrowEdge: .top) {
                RuleCapacityPopoverView(filterManager: filterManager)
            }
            #else
            .sheet(isPresented: $showingCapacityPopover) {
                RuleCapacityPopoverView(filterManager: filterManager)
            }
            #endif

            StatCard(
                title: "Enabled",
                value: "\(enabledListsCount)",
                icon: "checkmark.circle"
            )
            #if os(iOS)
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }
    }

    private func categoryHeader(_ category: FilterListCategory) -> some View {
        ListCategoryHeader(title: LocalizedStringKey(category.localizedName),
                           info: { selectedCategoryInfo = category },
                           anchorID: category.id,
                           isExpanded: foreignExpansion(for: category))
    }

    // The Foreign section is the one collapsible category; its disclosure lives
    // in the header on both platforms now that macOS no longer renders
    // AppKit's outline cell.
    private func foreignExpansion(for category: FilterListCategory) -> Binding<Bool>? {
        guard category == .foreign else { return nil }
        return Binding(
            get: { shouldExpandForeignFilters },
            set: { isExpanded in
                guard !showOnlyEnabledLists else { return }
                isForeignFiltersExpanded = isExpanded
            }
        )
    }

    private func defaultFilterNames(for category: FilterListCategory) -> [String] {
        FilterCategorySupport.defaultFilterNames(
            for: category,
            defaults: FilterListLoader().getDefaultFilterLists()
        )
    }

    private func regionalRecommendations(for languages: Set<String>) -> [FilterList] {
        let selected = Set(languages.map { $0.lowercased() })
        let matching = filterManager.filterLists.filter {
            $0.category == .foreign
                && !Set($0.languages.map { $0.lowercased() }).isDisjoint(with: selected)
        }
        return ForeignFilterOrganizer.recommendationBuckets(from: matching).recommended
    }

    private func applyRegionalRecommendations(_ languages: Set<String>) {
        let selected = Set(languages.map { $0.lowercased() })
        let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
        defaults.set(Array(selected).sorted(), forKey: "onboardingSelectedLanguages")
        let recommendedIDs = Set(regionalRecommendations(for: selected).map(\.id))
        for filter in filterManager.filterLists where filter.category == .foreign {
            guard recommendedIDs.contains(filter.id) || !filter.isCustom else { continue }
            filterManager.setFilterListSelection(id: filter.id, selected: recommendedIDs.contains(filter.id))
        }
        filterManager.flushPendingSave()
    }

    private func resetCategory(_ category: FilterListCategory) {
        if category == .foreign {
            let defaults = UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
            applyRegionalRecommendations(Set(defaults.stringArray(forKey: "onboardingSelectedLanguages") ?? []))
            return
        }

        let defaultNames = Set(defaultFilterNames(for: category))
        for filter in filterManager.filterLists {
            guard let selection = FilterCategorySupport.resetSelection(
                for: filter,
                category: category,
                defaultNames: defaultNames
            ) else { continue }
            filterManager.setFilterListSelection(id: filter.id, selected: selection)
        }
        filterManager.flushPendingSave()
    }

    private func refreshDownloadedFilterIDs() {
        let loader = filterManager.loader
        downloadedFilterIDs = Set(filterManager.filterLists.lazy.filter { loader.filterFileExists($0) }.map(\.id))
    }

    /// Confirm risky built-in lists before enabling or downloading them.
    /// The alert is attached to the info sheet too, because an open sheet blocks alerts from the view underneath.
    /// Returns whether `enable` ran now, so the info sheet stays open for the alert instead of dismissing under it.
    @discardableResult
    private func confirmingExperimental(_ filter: FilterList, _ enable: @escaping () -> Void) -> Bool {
        if let warning = RiskyFilterEnable(filter: filter, enable: enable) {
            pendingRiskyEnable = warning
            return false
        }
        enable()
        return true
    }

    private func downloadFilter(_ filter: FilterList) {
        guard filter.isRemoteURL, !filterManager.isLoading,
              !downloadingFilterIDs.contains(filter.id),
              !filterManager.loader.filterFileExists(filter) else { return }
        downloadingFilterIDs.insert(filter.id)
        Task {
            let succeeded = await filterManager.filterUpdater.fetchAndProcessFilter(filter)
            let current = filterManager.filterLists.first(where: { $0.id == filter.id })
            // One transaction, so the switch fades in already on instead of snapping.
            withAnimation(.easeInOut(duration: 0.2)) {
                downloadingFilterIDs.remove(filter.id)
                if succeeded, let current {
                    downloadedFilterIDs.insert(filter.id)
                    // Get also enables the list after its content is safely persisted.
                    filterManager.setFilterListSelection(id: current.id, selected: true)
                }
            }
            guard let current else { return }
            if succeeded {
                filterManager.saveFilterListsCoalesced()
                if current.isSelected { filterManager.markNonSelectionChangesPending() }
            } else {
                showingFilterDownloadError = true
            }
        }
    }

    private var orderedFilters: [FilterList] {
        FilterListPresentation.ordered(filterManager.filterLists, order: filterDisplayOrder)
    }

    private func moveFilter(_ id: UUID, to category: FilterListCategory) {
        guard category != .foreign,
              let index = filterManager.filterLists.firstIndex(where: { $0.id == id }),
              filterManager.filterLists[index].category != .foreign,
              filterManager.filterLists[index].category != category else { return }
        filterManager.filterLists[index].category = category
        filterManager.saveFilterListsCoalesced()
        // Moving a list back to where it was applied clears Apply again (#953).
        filterManager.refreshPendingChanges()
    }

    @ViewBuilder
    private func filterRows(_ filters: [FilterList]) -> some View {
        ReorderableRows(items: filters,
                        allItems: { orderedFilters }, order: $filterDisplayOrder) { filter in
            filterRowView(for: filter)
        }
    }

    private func filterRowView(for snapshot: FilterList) -> some View {
        // The presentation snapshot lands after an off-main sort with animations
        // off; reading it here made switches wait for it and then snap.
        let filter = filterManager.filterListIndex(for: snapshot.id).map { filterManager.filterLists[$0] } ?? snapshot
        let isDownloaded = downloadedFilterIDs.contains(filter.id)
        return FilterRowView(
            filter: filter,
            text: filterPresentation.rowText[filter.id] ?? .init(
                filter, isDownloaded: isDownloaded,
                lastModified: dataManager.getFilterLastModified(filter.id.uuidString)),
            isDownloaded: isDownloaded,
            isDownloading: downloadingFilterIDs.contains(filter.id),
            onDownload: { confirmingExperimental(filter) { downloadFilter(filter) } },
            onInfo: { selectedFilterInfo = filter },
            onSettings: { selectedFilterSettings = filter },
            onViewRules: { selectedFilterRules = filter },
            onEdit: { selectedFilterRules = filter },
            onEditInfo: { editingCustomFilter = filter },
            onDelete: { filterManager.removeFilterList(filter) },
            onToggle: { newValue in
                if !newValue && FilterListLoader.essentialFilterNames.contains(filter.name) {
                    pendingEssentialFilter = filter
                } else if newValue {
                    confirmingExperimental(filter) { filterManager.setFilterListSelection(id: filter.id, selected: true) }
                } else {
                    filterManager.setFilterListSelection(id: filter.id, selected: false)
                }
            }
        )
    }

    private func filterInfoContent(_ filter: FilterList) -> some View {
        FilterInfoView(
            filter: filter, filterManager: filterManager,
            isDownloading: downloadingFilterIDs.contains(filter.id),
            onDownload: { confirmingExperimental(filter) { downloadFilter(filter) } },
            onAction: macOSWindowAction { action in
                switch action {
                case .settings: selectedFilterSettings = filter
                case .editInfo: editingCustomFilter = filter
                case .fallbacks: selectedFilterFallbacks = filter
                default: selectedFilterRules = filter
                }
            }
        )
        .riskyFilterAlert($pendingRiskyEnable)
        .infoSheetPresentationCompat()
    }

    private func filterCategoryInfoContent(_ category: FilterListCategory) -> some View {
        FilterCategoryInfoView(
            category: category, defaultFilterNames: defaultFilterNames(for: category),
            filterLists: filterManager.filterLists, onLanguagesChange: applyRegionalRecommendations,
            onReset: { resetCategory(category) }
        ).infoSheetPresentationCompat()
    }

    #if os(macOS)
    private var macFilterSections: [MacListSection] {
        FilterListCategory.allCases.filter { $0 != .all && !$0.isUserScriptOnly }.compactMap { category in
            let filters = filterPresentation.sections.first { $0.category == category }?.filters ?? []
            if category == .foreign {
                guard !filters.isEmpty else { return nil }
                // Collapse is owned by the header's disclosure binding; the
                // section simply carries its rows only while expanded.
                let rows = shouldExpandForeignFilters ? filters.map { filter in
                    MacListRow(filter.id) { filterRowView(for: filter) }
                } : []
                return MacListSection(id: category.id, header: AnyView(categoryHeader(category)),
                                      rows: rows, allowsCrossSectionMoves: false)
            }
            let acceptsMoves = FilterListCategory.moveTargets.contains(category)
            guard acceptsMoves || !filters.isEmpty else { return nil }
            return MacListSection(id: category.id, header: AnyView(categoryHeader(category)),
                                  rows: filters.map { filter in
                                      MacListRow(filter.id, leavesSection: filter.isCustom) { filterRowView(for: filter) }
                                  },
                                  acceptsMoves: acceptsMoves, revealsOnlyWhileDragging: acceptsMoves)
        }
    }

    private func commitFilterMove(_ move: MacListMove) -> Bool {
        guard let category = FilterListCategory(rawValue: move.sectionID),
              let filter = filterManager.filterLists.first(where: { $0.id == move.itemID }),
              // Built-in lists keep the category wBlock gives them (#1028).
              filter.category == category
                || (filter.isCustom && FilterListCategory.moveTargets.contains(category)) else { return false }
        let all = orderedFilters
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let moved = move.orderedIDs.compactMap { byID[$0] }
        guard moved.count == move.orderedIDs.count else { return false }
        filterDisplayOrder = ListDisplayOrder.saving(moved, in: all)
        moveFilter(move.itemID, to: category)
        let live = Dictionary(uniqueKeysWithValues: filterManager.filterLists.map { ($0.id, $0) })
        let previous = filterPresentation.sections
        // Give the native outline the accepted arrangement immediately. The background
        // presentation task subsequently refreshes metadata and search results.
        filterPresentation.sections = FilterListCategory.allCases.compactMap { target in
            let rows = target == category ? move.orderedIDs.compactMap { live[$0] }
                : (previous.first { $0.category == target }?.filters.filter { $0.id != move.itemID } ?? [])
            return rows.isEmpty ? nil : FilterListPresentation.Section(category: target, filters: rows)
        }
        return true
    }
    #endif
}

struct FilterRowView: View {
    let filter: FilterList
    let text: FilterListPresentation.RowText
    let isDownloaded: Bool
    let isDownloading: Bool
    var onDownload: () -> Void
    var onInfo: () -> Void
    var onSettings: () -> Void
    var onViewRules: () -> Void
    var onEdit: () -> Void
    var onEditInfo: () -> Void
    var onDelete: () -> Void
    var onToggle: (Bool) -> Void

    @ViewBuilder
    private var contextMenuItems: some View {
        let actions = ContextMenuActionAvailability.filterActions(for: filter, isDownloaded: isDownloaded)
        if actions.contains(.info) {
            Button {
                onInfo()
            } label: {
                Label("Info", systemImage: "info.circle")
            }
        }
        if actions.contains(.download) {
            Button { onDownload() } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .disabled(isDownloading)
        }
        if actions.contains(.settings) {
            Button(action: onSettings) { Label("Settings", systemImage: "gearshape") }
        }
        if actions.contains(.viewRules) {
            Button {
                onViewRules()
            } label: {
                Label("View Rules", systemImage: "doc.text")
            }
        }
        if actions.contains(.editRules) {
            Button {
                onEdit()
            } label: {
                Label("Edit Rules", systemImage: "pencil")
            }
        }
        if actions.contains(.editInfo) {
            Button(action: onEditInfo) { Label("Edit Info", systemImage: "square.and.pencil") }
        }
        if actions.contains(.deleteList) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Added List", systemImage: "trash")
            }
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Keep the iOS info gesture on the text column so it cannot consume switch taps.
            filterDetails
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onInfo() }
                .contentShape(.interaction, Rectangle())
                #if os(iOS)
                .onTapGesture(perform: onInfo)
                #endif
            #if os(macOS)
            Button(action: onInfo) { Image(systemName: "info.circle") }
                .buttonStyle(.plain).noFocusRingCompat()
                .foregroundStyle(.secondary).accessibilityLabel("Info").help("Info")
                .infoPopoverAnchor(filter.id)
            #endif
            if filter.isRemoteURL && (isDownloading || !isDownloaded) {
                // A switch is meaningless until the list exists, so the row
                // offers Get in its place.
                ContentDownloadControl(
                    isDownloaded: isDownloaded, isDownloading: isDownloading,
                    name: text.name, action: onDownload
                )
            } else {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { filter.isSelected },
                        set: { newValue in
                            // Keep the explicit Toggle value across the deferred callback. The row's
                            // captured filter can be stale after another state update.
                            DispatchQueue.main.async {
                                onToggle(newValue)
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
            }
        }
        #if os(macOS)
        .contextMenu { contextMenuItems }
        .padding(16)
        #else
        // iOS keeps one control flush right. The chevron by the title says
        // the row opens; the Info sheet lists every action, and long press
        // is a shortcut to the same actions.
        .contextMenu { contextMenuItems }

        #endif
        .animation(.easeInOut(duration: 0.2), value: isDownloading)
        .animation(.easeInOut(duration: 0.2), value: isDownloaded)
    }

    private var filterDetails: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(text.name)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    #if os(iOS)
                    RowDisclosureChevron()
                    #endif
                    if filter.isInlineUserList {
                        Text("Local Import")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    } else if filter.isCustom {
                        Text("Custom")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.body)

                if !text.languages.isEmpty {
                    Text(text.languages)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !text.description.isEmpty {
                    Text(text.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        #if os(iOS)
                        .lineLimit(2)
                        #endif
                        .fixedSize(horizontal: false, vertical: true)
                }

                // One metadata line: rule count, version, and update time. The
                // Info sheet carries the full detail.
                if !text.metadata.isEmpty {
                    Text(text.metadata)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

}

#if os(iOS)
/// Size class rather than idiom decides the presentation, so the regular-width
/// inner display of iPhone Duo gets the sheet iPad already uses.
/// Onboarding is a sheet in regular width and full screen in compact width.
/// Both presenters stay attached and only their bindings follow the size class.
/// Branching on the size class swapped the whole view tree when Stage Manager
/// crossed the compact width, and the Apply sheet hosted on that tree came back
/// with no dimming behind it (#923).
private struct OnboardingPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let filterManager: AppFilterManager
    let onDismiss: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: presented(when: true), onDismiss: onDismiss) {
                OnboardingView(filterManager: filterManager)
            }
            .fullScreenCover(isPresented: presented(when: false), onDismiss: onDismiss) {
                OnboardingView(filterManager: filterManager)
            }
    }

    private func presented(when regular: Bool) -> Binding<Bool> {
        Binding(
            get: { isPresented && (horizontalSizeClass == .regular) == regular },
            set: { if !$0 { isPresented = false } }
        )
    }
}
#endif

struct ContentModifiers: ViewModifier {
    @ObservedObject var filterManager: AppFilterManager
    @ObservedObject var userScriptManager: UserScriptManager
    @ObservedObject var dataManager: ProtobufDataManager
    @Binding var showingAddFilterSheet: Bool
    let scenePhase: ScenePhase

    // Use explicit @State for sheet presentation to avoid computed binding issues
    @State private var showOnboardingSheet = false
    // Track if initial presentation check has been done to avoid re-showing after dismiss
    @State private var hasPerformedInitialCheck = false
    // False from the moment onboarding is requested until its dismissal finishes.
    // Onboarding requests Apply as it dismisses; presenting Apply on the same
    // host mid-dismissal crashed UIKit on iOS 16.
    @State private var onboardingSettled = true

    /// Update checks and their no-updates result float in a card over the app on
    /// every platform: on iOS a short sheet sits against the home bar, iOS 26 glass
    /// sheets ignore a clear background, and older iPads ignore detents; on the Mac
    /// the card dismisses itself and closes on a click like iOS (email feedback).
    private var checkCardVisible: Bool {
        onboardingSettled && !filterManager.showingApplyProgressSheet
            && (filterManager.showingNoUpdatesAlert || (filterManager.isLoading && !filterManager.suppressBlockingOverlay))
    }

    private var progressSheetPresented: Bool {
        onboardingSettled && filterManager.showingApplyProgressSheet
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingAddFilterSheet) {
                AddFilterListView(filterManager: filterManager)
            }
            .sheet(isPresented: Binding(
                get: { progressSheetPresented },
                set: { presented in
                    if !presented && !filterManager.isLoading {
                        filterManager.showingApplyProgressSheet = false
                        filterManager.showingNoUpdatesAlert = false
                    }
                }
            )) {
                ApplyChangesProgressView(
                    filterManager: filterManager,
                    viewModel: filterManager.applyProgressViewModel,
                    isPresented: $filterManager.showingApplyProgressSheet
                )
            }
            .overlay {
                if checkCardVisible {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                            .onTapGesture { filterManager.showingNoUpdatesAlert = false }
                        UpdateCheckProgressView(filterManager: filterManager)
                    }
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: checkCardVisible)
            .onChangeCompat(of: showOnboardingSheet) { _, presented in
                if presented { onboardingSettled = false }
            }
            .alert("Filters Auto-Disabled", isPresented: $filterManager.showingAutoDisabledAlert) {
                Button("OK") {}
            } message: {
                if filterManager.autoDisabledFilters.isEmpty {
                    Text("Some filters were automatically disabled because Safari's rule limits were exceeded.")
                } else {
                    let filterNames = filterManager.autoDisabledFilters
                        .map(\.localizedDisplayName)
                        .joined(separator: "\n")
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString(
                                "The following filters were automatically disabled:\n\n%@\n\nTo re-enable these filters, disable other large filters and apply changes again.",
                                comment: "Auto-disabled filters alert"
                            ),
                            filterNames
                        )
                    )
                }
            }
            .alert(
                "Duplicate Userscripts Found",
                isPresented: $userScriptManager.showingDuplicatesAlert
            ) {
                Button("Remove Older Versions", role: .destructive) {
                    userScriptManager.confirmDuplicateRemoval()
                }
                Button("Keep All", role: .cancel) {
                    userScriptManager.cancelDuplicateRemoval()
                }
            } message: {
                Text(userScriptManager.duplicatesMessage)
            }
            .onAppear {
                filterManager.setUserScriptManager(userScriptManager)
            }
            // Show onboarding/setup sheets only on initial load
            .task {
                await dataManager.waitUntilLoaded()
                // Only check once on initial load
                if !hasPerformedInitialCheck {
                    hasPerformedInitialCheck = true
                    updateSheetPresentation()
                }
            }
            // React to hasCompletedOnboarding changes
            .onChangeCompat(of: dataManager.hasCompletedOnboarding) { oldValue, newValue in
                if newValue && !oldValue {
                    showOnboardingSheet = false
                } else if !newValue && oldValue {
                    // Onboarding was reset (e.g., from Settings), show onboarding again
                    showOnboardingSheet = true
                }
            }
            #if os(iOS)
                .onChangeCompat(of: scenePhase) { _, newPhase in
                    if newPhase == .background && filterManager.hasUnappliedChanges {
                        scheduleNotification(delay: 1)
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .applyWBlockChangesNotification)
                ) { _ in
                    applyFilterChangesFromExternalTrigger()
                }
                .modifier(OnboardingPresentationModifier(
                    isPresented: $showOnboardingSheet,
                    filterManager: filterManager,
                    onDismiss: onboardingDismissed
                ))
            #elseif os(macOS)
                .sheet(isPresented: $showOnboardingSheet, onDismiss: onboardingDismissed) {
                    OnboardingView(filterManager: filterManager)
                }
            #endif
    }

    /// A size-class swap dismisses one onboarding presenter while the other stays up.
    private func onboardingDismissed() {
        onboardingSettled = !showOnboardingSheet
    }

    /// Determines which sheet (if any) should be shown on initial app load.
    /// Called only once after initial data load completes.
    private func updateSheetPresentation() {
        if !dataManager.hasCompletedOnboarding {
            showOnboardingSheet = true
        }
    }

    private func applyFilterChangesFromExternalTrigger() {
        guard !filterManager.isLoading else { return }
        filterManager.checkAndEnableFilters(forceReload: true)
    }

    #if os(iOS)
        private func scheduleNotification(delay: TimeInterval = 1.0) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Psst! You forgot something!")
            content.body = String(localized: "You have unapplied filter changes in wBlock. Tap to apply them now!")
            content.sound = .default
            content.userInfo = ["action_type": "apply_wblock_changes"]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { _ in }
        }
    #endif
}

extension FilterListCategory {
    static var userListCategories: [FilterListCategory] {
        [.custom] + allCases.filter { $0 != .all && $0 != .custom && $0 != .scripts && !$0.isUserScriptOnly }
    }

    /// Categories a filter list can be moved into, including ones with no lists yet.
    static var moveTargets: [FilterListCategory] {
        allCases.filter { $0 != .all && $0 != .foreign && $0 != .scripts && !$0.isUserScriptOnly }
    }
}

private func userListCategoryPicker(selection: Binding<FilterListCategory>) -> some View {
    ContentCategoryPicker(selection: selection, categories: FilterListCategory.userListCategories)
}


struct FilterListAddValidation {
    static func isDuplicateName(candidate: String, existingNames: [String]) -> Bool {
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCandidate.isEmpty else { return false }
        return existingNames.contains {
            $0.caseInsensitiveCompare(trimmedCandidate) == .orderedSame
        }
    }
}

struct AddFilterListView: View {
    @ObservedObject var filterManager: AppFilterManager

	@Environment(\.dismiss) private var dismiss
	@FocusState private var urlFieldIsFocused: Bool

    @State private var isReviewingURLs = false
    @State private var urlCategories: [String: FilterListCategory] = [:]
    @State private var urlLanguages: [String: Set<String>] = [:]
    @State private var userListLanguages: Set<String> = []
    @State private var urlEntryMode: URLEntryMode = .single
    @State private var urlInput: String = ""
    @State private var isReviewingText = false
    @State private var textMetadataState = EditorMetadataAutofillState()
    @State private var customURLNames: [String: String] = [:]
    @State private var customURLDescriptions: [String: String] = [:]
    @StateObject private var urlReview = URLImportReviewCoordinator(identity: FilterListURLSupport.identityKey(for:))
    @State private var submittedURLs: [URL]?
    @State private var isSaving: Bool = false
    /// Names as they were before this add saved. The list being added must
    /// not flag itself as a duplicate while the sheet closes (#955).
    @State private var namesBeforeSave: [String]?
    @State private var showingFileImporter = false
    @State private var importErrorMessage: String?
    @State private var pastedRules: String = ""
    @State private var isShowingRulesEditor = false
    @StateObject private var rulesEditorController = CodeMirrorEditorController(text: "", language: .filterRules, classifiesRules: true)
    @State private var userListTitle: String = ""
    @State private var userListDescription: String = ""
    @State private var selectedCategory: FilterListCategory = .custom
    @State private var stagedFile: StagedFilterFile?
    @State private var isStagingFile = false
    @State private var stagingGeneration = 0
    @State private var importsURLList = false
    /// Set when Find hands over a registry list: the URL change it makes goes
    /// straight to review instead of resetting it.
    @State private var reviewsNextURLInput = false

    private struct StagedFilterFile {
        let filename: String
        let content: String
    }

    private enum URLEntryMode: String, CaseIterable, Identifiable {
        case single
        case bulk

        var id: String { rawValue }
    }

    private enum AddMode: String, CaseIterable, Identifiable, AddContentMode {
        case url = "URL"
        case paste = "Text"
        case file = "File"
        case find = "Browse"

        var id: String { rawValue }
        var localizedTitle: LocalizedStringKey { LocalizedStringKey(rawValue) }
        var systemImage: String {
            switch self {
            case .url: return "link"
            case .paste: return "text.alignleft"
            case .file: return "doc"
            case .find: return "magnifyingglass"
            }
        }
    }

    @State private var addMode: AddMode = .url
    @State private var findQuery = ""
    /// The URL review was opened from Find, so Back returns there (#987).
    @State private var isReviewingFromFind = false
    /// URL tab text from before Find staged a list, restored on the way back.
    @State private var urlInputBeforeFind = ""


    private var parsedURLInput: FilterListURLParseResult {
        FilterListURLSupport.parseRemoteURLs(from: urlInput)
    }

    private var newURLs: [URL] {
        if let submittedURLs { return submittedURLs }
        let existingKeys = Set(filterManager.filterLists.map { FilterListURLSupport.identityKey(for: $0.url) })
        var seen = Set<String>()
        return parsedURLInput.urls.filter { url in
            let key = FilterListURLSupport.identityKey(for: url)
            return !existingKeys.contains(key) && seen.insert(key).inserted
        }
    }

    private var existingURLCount: Int {
        parsedURLInput.urls.count - newURLs.count
    }

    private var validationState: ValidationState {
        validationState(for: urlInput)
    }

    var body: some View {
        AddContentSheet(
            title: "Add Filter List",
            mode: $addMode,
            isLoading: isSaving,
            submitTitle: LocalizedStringKey(addButtonTitle),
            isSubmitDisabled: !canSubmit || isSaving || urlReview.isImportingFile || (isReviewingURLs && urlReview.isFetchingMetadata),
            onDismiss: { dismiss() },
            onSubmit: submit,
            // Find adds each list as you tap it, so Done is the only way out.
            showsCancel: addMode != .find,
            onBack: backAction
        ) { mode in
            modeContent(mode)
        }
        .onChangeCompat(of: urlInput) { oldValue, newValue in
            isReviewingURLs = reviewsNextURLInput
            reviewsNextURLInput = false
            let normalized: String
            if urlEntryMode == .single {
                normalized = FilterListURLSupport.normalizeSingleURLInput(from: oldValue, to: newValue)
            } else {
                normalized = FilterListURLSupport.normalizeURLInput(from: oldValue, to: newValue)
            }
            if normalized != newValue {
                urlInput = normalized
            } else {
                syncURLMetadataFields()
                fetchMetadataForCurrentURLs()
            }
        }
        .onChangeCompat(of: urlEntryMode) { oldValue, newValue in
            cancelURLListImport()
            isReviewingURLs = false
            if newValue == .single {
                urlInput = FilterListURLSupport.normalizeSingleURLInput(urlInput)
            } else {
                urlInput = FilterListURLSupport.normalizeURLInput(urlInput, rejoinWrappedLines: false)
            }
            syncURLMetadataFields()
            fetchMetadataForCurrentURLs()
        }
        .onChangeCompat(of: addMode) { _, mode in
            if mode != .url && isReviewingFromFind {
                isReviewingFromFind = false
                isReviewingURLs = false
                urlInput = urlInputBeforeFind
            }
            cancelURLListImport()
            if mode == .url { fetchMetadataForCurrentURLs() } else {
                urlReview.cancelMetadata()
            }
        }
        .onChangeCompat(of: pastedRules) { _, _ in isReviewingText = false }
        .onChangeCompat(of: userListTitle) { _, newValue in
            if addMode == .paste { textMetadataState.noteNameEdit(newValue) }
        }
        .onChangeCompat(of: userListDescription) { _, newValue in
            if addMode == .paste { textMetadataState.noteDescriptionEdit(newValue) }
        }
        .onDisappear {
            urlReview.cancelMetadata()
        }
        #if os(macOS)
	    .onAppear {
	        urlFieldIsFocused = addMode == .url
	    }
        .onChangeCompat(of: addMode) { _, newValue in
            urlFieldIsFocused = newValue == .url
        }
        #endif
        .sheet(isPresented: $isShowingRulesEditor) {
            SourceEditorSheet(title: "Rules", editorController: rulesEditorController) { text in
                pastedRules = text
                return nil
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: importsURLList ? [.plainText, .text] : filterImportTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if importsURLList { importURLList(from: url) } else { stageFile(at: url) }
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    importErrorMessage = error.localizedDescription
                }
            }
        }
        .alert(
            "Couldn’t Add List",
            isPresented: Binding(get: { importErrorMessage != nil }, set: { _ in importErrorMessage = nil })
        ) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
	        }
	    }

    private var backAction: (() -> Void)? {
        switch addMode {
        case .url where isReviewingURLs:
            return {
                isReviewingURLs = false
                urlReview.cancelMetadata()
                if isReviewingFromFind { addMode = .find }
            }
        case .paste where isReviewingText:
            return { isReviewingText = false }
        default:
            return nil
        }
    }

    @ViewBuilder
    private func modeContent(_ mode: AddMode) -> some View {
        switch mode {
        case .url:
            if isReviewingURLs {
                Section {
                    if urlReview.isFetchingMetadata { ProgressView().controlSize(.small) }
                } footer: {
                    if !isSaving { urlFooterMessage }
                }
                urlMetadataSections
            } else {
                Section {
                    urlEntryModePicker
                    urlInputEditor
                } footer: {
                    if !isSaving { urlFooterMessage }
                }
            }
        case .paste:
            if isReviewingText {
                Section { userListMetaFields } footer: { duplicateNameNote(for: userListTitle) }
            } else {
                AddContentSourceSection(title: "Rules", placeholder: "Paste or type filter rules.",
                    isEmpty: pastedRules.isEmpty, isDisabled: isSaving, onPaste: pasteRulesFromClipboard,
                    onOpenEditor: {
                        rulesEditorController.replaceText(pastedRules, markClean: true)
                        isShowingRulesEditor = true
                    }, font: SyntaxHighlightingTextView.font, textInsets: SyntaxHighlightingTextView.textInsets) {
                        SyntaxHighlightingTextView(text: $pastedRules)
                    } footer: {
                        AddContentNote(text: "Local imports won't auto-update; re-import to replace.")
                    }
            }
        case .file:
            Section {
                AddContentFileSelectionButton(
                    filename: stagedFile?.filename,
                    isLoading: isStagingFile,
                    isDisabled: isSaving
                ) {
                    importsURLList = false
                    showingFileImporter = true
                    importErrorMessage = nil
                }
                if stagedFile != nil { userListMetaFields }
            } footer: {
                AddContentNote(text: "Local imports won't auto-update; re-import to replace.", error: importErrorMessage)
                if stagedFile != nil { duplicateNameNote(for: userListTitle) }
            }
        case .find:
            FilterRegistrySearchSections(filterManager: filterManager, query: $findQuery, onAdd: review)
        }
    }

    /// Opens a registry list in URL review with the registry's name,
    /// description, category, and languages as the automatic values.
    private func review(_ list: AdGuardRegistryList) {
        let url = list.filter.url
        urlReview.metadata[FilterListURLSupport.identityKey(for: url)] =
            .init(title: list.filter.name, description: list.filter.description)
        urlCategories[url.absoluteString] = list.filter.category
        urlLanguages[url.absoluteString] = Set(list.filter.languages)
        if !isReviewingFromFind { urlInputBeforeFind = urlInput }
        addMode = .url
        isReviewingFromFind = true
        let input = urlEntryMode == .single
            ? url.absoluteString
            : UserScriptURLSupport.appendingPastedURLs(url.absoluteString, to: urlInput)
        if input == urlInput {
            isReviewingURLs = true
        } else {
            reviewsNextURLInput = true
            urlInput = input
        }
    }

    private var urlEntryModePicker: some View {
        Picker("URL entry mode", selection: $urlEntryMode) {
            Text("Single URL").tag(URLEntryMode.single)
            Text("Bulk URLs").tag(URLEntryMode.bulk)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(isSaving)
    }

    private var urlMetadataSections: some View {
        ForEach(newURLs, id: \.absoluteString) { url in
            AddContentURLMetadataSection(
                url: url,
                name: nameBinding(for: url),
                description: descriptionBinding(for: url),
                category: Binding(
                    get: { urlCategories[url.absoluteString] ?? selectedCategory },
                    set: { urlCategories[url.absoluteString] = $0 }
                ),
                categories: FilterListCategory.userListCategories,
                languages: Binding(
                    get: { urlLanguages[url.absoluteString] ?? [] },
                    set: { urlLanguages[url.absoluteString] = $0 }
                )
            ) {
                duplicateNameNote(for: nameBinding(for: url).wrappedValue)
            }
        }
    }

    private var urlInputEditor: some View {
        AddContentURLInput(
            text: $urlInput,
            isFocused: $urlFieldIsFocused,
            isBulk: urlEntryMode == .bulk,
            placeholder: urlEntryMode == .single
                ? Text(verbatim: "https://example.com/filter.txt")
                : Text("Paste one or more filter URLs, one per line."),
            label: urlEntryMode == .single ? "URL" : "URLs",
            isDisabled: isSaving,
            onPaste: pasteURLsFromClipboard,
            pasteTitle: urlEntryMode == .single ? "Paste URL" : "Paste URLs",
            onImportFile: { importsURLList = true; showingFileImporter = true },
            isImportingFile: urlReview.isImportingFile
        )
    }

    // MARK: - Footer
	    private var urlFooterMessage: some View {
	        Group {
	            if !isReviewingURLs {
	                switch validationState {
	                case .idle:
	                    Text("wBlock will fetch and enable the filter list automatically")
                            .foregroundStyle(.secondary)
	                case .invalid:
                        if urlEntryMode == .single {
                            Text("This isn’t a valid http(s) filter URL.")
                                .foregroundStyle(.orange)
                        } else if let lineNumber = parsedURLInput.invalidLineNumbers.first {
                            Text(LocalizedStrings.format(
                                "Line %d isn’t a valid http(s) filter URL.",
                                comment: "Invalid bulk filter URL line",
                                lineNumber
                            ))
                            .foregroundStyle(.orange)
                        }
	                case .duplicate:
                        Text(parsedURLInput.urls.count == 1
                            ? LocalizedStrings.text(
                                "A filter list with this URL already exists in wBlock.",
                                comment: "Single duplicate filter URL validation"
                            )
                            : LocalizedStrings.text(
                                "All of these filter lists are already in wBlock.",
                                comment: "Bulk duplicate filter URL validation"
                            ))
	                        .foregroundStyle(.orange)
	                case .valid:
                        if existingURLCount > 0 {
                            Text("Existing filter lists will be skipped.")
                                .foregroundStyle(.secondary)
                        }
	                }
	            }
	        }
	        .font(.footnote)
	    }

    private var canSubmit: Bool {
        if isSaving || isCustomNameDuplicate { return false }
        switch addMode {
        case .url:
            if case .valid = validationState { return true }
            return false
        case .paste:
            return (!isReviewingText || !userListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                && !pastedRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file:
            return !isStagingFile
                && stagedFile != nil
                && !userListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .find:
            return true
        }
    }

    private func submit() {
        switch addMode {
        case .find:
            dismiss()
        case .url:
            guard case .valid(let urls) = validationState else { return }
            if !isReviewingURLs {
                isReviewingURLs = true
                urlFieldIsFocused = false
                fetchMetadataForCurrentURLs()
                return
            }
            submittedURLs = urls
            beginSaving()
            Task { @MainActor in
                for url in urls {
                    let key = FilterListURLSupport.identityKey(for: url)
                    let automaticName = automaticName(for: url)
                    let name = ImportMetadataReview.userProvided(customURLNames[key], automatic: automaticName)
                    let automaticDescription = urlReview.metadata[key]?.description
                    let description = ImportMetadataReview.userProvided(
                        customURLDescriptions[key], automatic: automaticDescription)
                    filterManager.addFilterList(
                        name: name.flatMap { $0.isEmpty ? nil : $0 } ?? automaticName,
                        urlString: url.absoluteString,
                        category: urlCategories[url.absoluteString] ?? selectedCategory,
                        hasUserProvidedName: name?.isEmpty == false,
                        hasUserProvidedDescription: description != nil,
                        description: description ?? automaticDescription,
                        languages: Array(urlLanguages[url.absoluteString] ?? [])
                    )
                }
                dismiss()
            }
        case .paste:
            if !isReviewingText {
                if let message = AppFilterManager.userListContentError(pastedRules) {
                    importErrorMessage = message
                    return
                }
                let metadata = FilterListMetadataParser.parse(from: pastedRules, maxLines: 80)
                let values = textMetadataState.autofill(
                    name: metadata.title ?? "",
                    description: metadata.description ?? "",
                    currentName: userListTitle,
                    currentDescription: userListDescription
                )
                userListTitle = values.name
                userListDescription = values.description
                isReviewingText = true
                return
            }
            beginSaving()
            Task { @MainActor in
                let finalName = userListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalDescription = userListDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalRules = pastedRules.trimmingCharacters(in: .whitespacesAndNewlines)
                filterManager.addUserList(
                    name: finalName,
                    description: finalDescription.isEmpty ? nil : finalDescription,
                    content: finalRules,
                    category: selectedCategory,
                    isSelected: true,
                    languages: Array(userListLanguages)
                )
                isSaving = false
                if !filterManager.hasError {
                    dismiss()
                } else {
                    namesBeforeSave = nil
                    importErrorMessage = filterManager.statusDescription
                }
            }
        case .file:
            guard let stagedFile else { return }
            beginSaving()
            Task { @MainActor in
                let finalName = userListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalDescription = userListDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                filterManager.addUserList(
                    name: finalName,
                    description: finalDescription.isEmpty ? nil : finalDescription,
                    content: stagedFile.content,
                    category: selectedCategory,
                    isSelected: true,
                    languages: Array(userListLanguages)
                )
                isSaving = false
                if !filterManager.hasError {
                    dismiss()
                } else {
                    namesBeforeSave = nil
                    importErrorMessage = filterManager.statusDescription
                }
            }
        }
    }

    private var addButtonTitle: String {
        if (addMode == .url && !isReviewingURLs) || (addMode == .paste && !isReviewingText) { return "Next" }
        switch addMode {
        case .url:
            if newURLs.count > 1 {
                return LocalizedStrings.text(
                    "Add URLs",
                    comment: "Bulk filter URL add button"
                )
            }
            return "Add"
        case .paste, .file: return "Add"
        case .find: return "Done"
        }
    }

    private var userListMetaFields: some View {
        AddContentMetadataFields(name: $userListTitle, description: $userListDescription,
                                 category: $selectedCategory, categories: FilterListCategory.userListCategories,
                                 languages: $userListLanguages)
    }

    private var filterImportTypes: [UTType] {
        FilterListContentValidator.supportedLocalFileExtensions.compactMap {
            UTType(filenameExtension: $0, conformingTo: .plainText)
        }
    }

    // MARK: - Helpers

    private func pasteRulesFromClipboard() {
        #if os(iOS)
        if let string = UIPasteboard.general.string { pastedRules = string }
        #elseif os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) { pastedRules = string }
        #endif
    }

    private func pasteURLsFromClipboard() {
        #if os(iOS)
        let pasted = UIPasteboard.general.string
        #else
        let pasted = NSPasteboard.general.string(forType: .string)
        #endif
        guard let pasted else { return }
        if urlEntryMode == .single {
            urlInput = FilterListURLSupport.normalizeSingleURLInput(pasted)
        } else {
            urlInput = UserScriptURLSupport.appendingPastedURLs(pasted, to: urlInput)
        }
    }

    private func automaticName(for url: URL) -> String {
        let title = trimmed(urlReview.metadata[FilterListURLSupport.identityKey(for: url)]?.title)
        return title.isEmpty ? defaultName(for: url) : title
    }

    private func nameBinding(for url: URL) -> Binding<String> {
        let key = FilterListURLSupport.identityKey(for: url)
        return Binding(
            get: { customURLNames[key] ?? automaticName(for: url) },
            set: { customURLNames[key] = Self.singleLineMetadataField($0) }
        )
    }

    private func descriptionBinding(for url: URL) -> Binding<String> {
        let key = FilterListURLSupport.identityKey(for: url)
        return Binding(
            get: { customURLDescriptions[key] ?? urlReview.metadata[key]?.description ?? "" },
            set: { customURLDescriptions[key] = Self.singleLineMetadataField($0) }
        )
    }

    private func syncURLMetadataFields() {
        let keys = Set(newURLs.map { FilterListURLSupport.identityKey(for: $0) })
        customURLNames = customURLNames.filter { keys.contains($0.key) }
        customURLDescriptions = customURLDescriptions.filter { keys.contains($0.key) }
        urlReview.metadata = urlReview.metadata.filter { keys.contains($0.key) }
    }

    private static func singleLineMetadataField(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private func fetchMetadataForCurrentURLs() {
        urlReview.fetchMetadata(for: newURLs, isReviewing: isReviewingURLs)
    }

    private func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func cancelURLListImport() {
        urlReview.cancelFileImport()
    }

    private func importURLList(from url: URL) {
        isReviewingURLs = false
        importErrorMessage = nil
        urlReview.importURLList(from: url, onSuccess: { text in
            urlInput = UserScriptURLSupport.appendingPastedURLs(text, to: urlInput)
        }, onFailure: { importErrorMessage = $0 })
    }

    private func stageFile(at url: URL) {
        stagingGeneration += 1
        let generation = stagingGeneration
        isStagingFile = true
        importErrorMessage = nil
        let didAccess = url.startAccessingSecurityScopedResource()

        Task { @MainActor in
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    () throws -> (content: String, title: String?, description: String?) in
                    guard FilterListContentValidator.isSupportedLocalFile(url) else {
                        throw NSError(domain: "wBlock.filterImport", code: 3, userInfo: [
                            NSLocalizedDescriptionKey: LocalizedStrings.text(
                                "That doesn't look like a filter list.",
                                comment: "User list validation error"
                            )
                        ])
                    }
                    let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard fileSize <= UserScriptImportLimits.maximumSourceFileBytes else {
                        throw NSError(domain: "wBlock.filterImport", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: LocalizedStrings.text(
                                "The selected file is too large. Maximum size is 10 MB.",
                                comment: "Local filter import size error"
                            )
                        ])
                    }
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let error = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? LocalizedStrings.text("That doesn't look like a filter list.", comment: "User list validation error")
                        : AppFilterManager.userListContentError(content)
                    if let error {
                        throw NSError(domain: "wBlock.filterImport", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: error
                        ])
                    }

                    let metadata = FilterListMetadataParser.parse(from: content, maxLines: 80)
                    return (content, metadata.title, metadata.description)
                }.value

                guard generation == stagingGeneration else { return }
                stagedFile = StagedFilterFile(filename: url.lastPathComponent, content: result.content)
                let metadataTitle = result.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                userListTitle = metadataTitle.isEmpty ? fallbackFileName(for: url) : metadataTitle
                userListDescription = result.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                isStagingFile = false
            } catch {
                guard generation == stagingGeneration else { return }
                isStagingFile = false
                importErrorMessage = error.localizedDescription
            }
        }
    }

    private func fallbackFileName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "User List" : name
    }

    private func validationState(for rawValue: String) -> ValidationState {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .idle
        }

        let parsed = FilterListURLSupport.parseRemoteURLs(from: rawValue)
        guard parsed.invalidLineNumbers.isEmpty, !parsed.urls.isEmpty else {
            return .invalid
        }

        guard !newURLs.isEmpty else {
            return .duplicate
        }

        return .valid(newURLs)
    }

    private func defaultName(for url: URL) -> String {
        let lastComponent = url.deletingPathExtension().lastPathComponent
        if lastComponent.isEmpty {
            return url.host ?? "Custom Filter"
        }
        return lastComponent.replacingOccurrences(of: "-", with: " ").replacingOccurrences(
            of: "_", with: " "
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isCustomNameDuplicate: Bool {
        duplicateNameCandidates.contains(where: isDuplicateName)
    }

    /// Every name the add would save. Reviewed URLs count with their fetched
    /// titles too, not just typed names, and every URL is checked (#948).
    /// Only names on screen count, so a name left in another step can't
    /// quietly disable Next (#952).
    private var duplicateNameCandidates: [String] {
        switch addMode {
        case .url: return isReviewingURLs ? newURLs.map { nameBinding(for: $0).wrappedValue } : []
        case .paste: return isReviewingText ? [userListTitle] : []
        case .file: return stagedFile != nil ? [userListTitle] : []
        case .find: return []
        }
    }

    private func isDuplicateName(_ name: String) -> Bool {
        FilterListAddValidation.isDuplicateName(
            candidate: name, existingNames: namesBeforeSave ?? filterManager.filterLists.map(\.name))
    }

    private func beginSaving() {
        namesBeforeSave = filterManager.filterLists.map(\.name)
        isSaving = true
    }

    /// Under the name it's about, in every add mode (#952).
    @ViewBuilder
    private func duplicateNameNote(for name: String) -> some View {
        if isDuplicateName(name) {
            AddContentNote(error: LocalizedStrings.text("That name is already used by another filter list."))
        }
    }

    private enum ValidationState: Equatable {
        case idle
        case invalid
        case duplicate
        case valid([URL])
    }

}

struct EditCustomFilterView: View {
    @ObservedObject var filterManager: AppFilterManager
    let filter: FilterList

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFieldIsFocused: Bool

    @State private var name: String
    @State private var description: String
    @State private var selectedCategory: FilterListCategory
    @State private var languages: Set<String>
    @State private var errorMessage: String?

    init(filterManager: AppFilterManager, filter: FilterList) {
        self.filterManager = filterManager
        self.filter = filter
        self._name = State(initialValue: filter.name)
        self._description = State(initialValue: filter.description)
        self._selectedCategory = State(initialValue: filter.category)
        self._languages = State(initialValue: Set(filter.languages))
    }

    var body: some View {
        Group {
            #if os(iOS)
                CompatibleNavigationStack {
                    Form {
                        Section {
                            TextField("Name", text: $name)
                                .focused($nameFieldIsFocused)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit {
                                    if canSave {
                                        save()
                                    } else {
                                        nameFieldIsFocused = false
                                    }
                                }

                            TextField("Description", text: $description)
                            userListCategoryPicker(selection: $selectedCategory)
                            RegionalListLanguagesField(category: selectedCategory, languages: $languages)

                            if !filter.isInlineUserList {
                                Text(filter.url.absoluteString)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        } footer: {
                            if isDuplicate {
                                Text("That name is already used by another filter list.")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .navigationTitle("Edit Filter List")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { save() }
                                .disabled(!canSave)
                        }
                    }
                }
                .onAppear {
                    nameFieldIsFocused = true
                }
            #else
                SheetContainer {
                    SheetHeader(title: "Edit Filter List") {
                        dismiss()
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Name")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                TextField("Filter name", text: $name)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($nameFieldIsFocused)
                                    .onSubmit {
                                        if canSave {
                                            save()
                                        } else {
                                            nameFieldIsFocused = false
                                        }
                                    }

                                TextField("Description", text: $description)
                                    .textFieldStyle(.roundedBorder)
                                userListCategoryPicker(selection: $selectedCategory)
                                RegionalListLanguagesField(category: selectedCategory, languages: $languages)

                                if !filter.isInlineUserList {
                                    Text(filter.url.absoluteString)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                }

                                if isDuplicate {
                                    Text("That name is already used by another filter list.")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                    }

                    SheetBottomToolbar {
                        Spacer()
                        saveButton
                    }
                }
                .onAppear {
                    nameFieldIsFocused = true
                }
            #endif
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { _ in errorMessage = nil }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        let candidate = trimmedName
        guard !candidate.isEmpty else { return false }
        return filterManager.filterLists.contains(where: {
            $0.id != filter.id && $0.name.caseInsensitiveCompare(candidate) == .orderedSame
        })
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isDuplicate
    }

    private var saveButton: some View {
        Button("Save") {
            save()
        }
        .primaryActionButtonStyle()
        .disabled(!canSave)
        .keyboardShortcut(.defaultAction)
    }

    private func save() {
        if filterManager.updateCustomFilterList(
            id: filter.id,
            name: trimmedName,
            category: selectedCategory,
            description: description,
            languages: Array(languages)
        ) {
            dismiss()
        } else {
            errorMessage = filterManager.statusDescription
        }
    }
}

/// Inline user lists open straight into the shared source editor (#921).
struct EditUserListView: View {
    @ObservedObject var filterManager: AppFilterManager
    let filter: FilterList

    @StateObject private var editorController = CodeMirrorEditorController(text: "", language: .filterRules, classifiesRules: true)
    @State private var isLoaded = false

    var body: some View {
        Group {
            if isLoaded {
                SourceEditorSheet(title: filter.localizedDisplayName, editorController: editorController) { text in
                    filterManager.updateUserList(
                        id: filter.id, name: filter.name, description: filter.description,
                        category: filter.category, content: text
                    )
                    return filterManager.hasError ? filterManager.statusDescription : nil
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(macOS)
                    .frame(width: 1000, height: 700)
                    #endif
            }
        }
        .task {
            let snapshot = filter
            let rules = await Task.detached { FilterListLoader().readLocalFilterContent(snapshot) ?? "" }.value
            editorController.replaceText(rules, markClean: true)
            isLoaded = true
        }
    }
}

struct RuleCapacityPopoverView: View {
    @ObservedObject var filterManager: AppFilterManager
    @Environment(\.dismiss) private var dismiss

    private var targets: [ContentBlockerTargetInfo] {
        ContentBlockerTargetManager.shared.allTargets(forPlatform: filterManager.currentPlatform)
    }

    private var totalUsed: Int {
        filterManager.lastRuleCount
    }

    private var totalCapacity: Int {
        filterManager.safariRuleCapacity
    }

    /// Rules in the enabled source lists before Safari conversion. Conversion
    /// merges and drops rules Safari cannot express, so this is usually larger
    /// than the Safari total (#624).
    private var sourceRules: Int {
        filterManager.filterLists
            .filter(\.isSelected)
            .reduce(0) { $0 + ($1.sourceRuleCount ?? 0) }
    }

    private var overallFraction: Double {
        filterManager.safariRuleCapacityFraction
    }

    var body: some View {
        #if os(macOS)
        capacityContent
            .padding(16)
            .frame(width: 340)
        #else
        capacitySheetContent
            .frame(idealWidth: 560, maxWidth: 560, maxHeight: .infinity, alignment: .top)
            .largeSheetPresentationCompat()
            .fittedFormSheetSizingCompat()
        #endif
    }

    #if !os(macOS)
    private var capacityColumn: some View {
        capacityContent
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
    }

    /// Keep the scroll indicator beside the content and scroll only when
    /// the expanded capacity panel cannot fit vertically.
    @ViewBuilder
    private var capacitySheetContent: some View {
        if #available(iOS 16.0, *) {
            ViewThatFits(in: .vertical) {
                capacityColumn
                capacityScrollView
            }
        } else {
            capacityScrollView
        }
    }

    private var capacityScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            capacityColumn
        }
        .scrollBounceBasedOnSizeCompat()
    }
    #endif

    private var capacityContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Safari Rule Capacity", systemImage: "shield.lefthalf.filled")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Spacer()
                SheetDoneButton { dismiss() }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Total Capacity")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(totalUsed.formatted()) / \(totalCapacity.formatted()) rules (\(LocalizedFormatting.percent(overallFraction)))")
                        .font(.caption)
                        .foregroundStyle(overallFraction > 0.8 ? Color.orange : Color.secondary)
                }

                ruleTypeBar(
                    hiding: filterManager.appliedRuleCounts?.elementHiding ?? 0,
                    total: totalUsed, capacity: totalCapacity
                )
                .frame(height: 8)

                if sourceRules > 0 {
                    HStack {
                        Text("Source Rules")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(
                            LocalizedStrings.format(
                                "%@ → %@ Safari rules",
                                comment: "Rule capacity popover: source rule count converted to Safari rule count",
                                sourceRules.formatted(),
                                totalUsed.formatted()
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
            }
            .padding(12)
            .liquidGlassCompat(cornerRadius: 12, material: .regularMaterial)

            if let applied = filterManager.appliedRuleCounts, totalUsed > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rule Types")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ruleTypeRow(.network, count: max(0, totalUsed - applied.elementHiding))
                    ruleTypeRow(.elementHiding, count: applied.elementHiding)
                    ruleTypeRow(.advanced, title: "wBlock Scripts", count: applied.scripts)
                    ruleTypeRow(.removeParam, count: applied.urlParameters, limit: RemoveParamDNRRuleGenerator.maxGeneratedRules)
                    Text(
                        LocalizedStrings.format(
                            "Network and element hiding rules count toward Safari's limit. wBlock Scripts applies its rules on its own, and URL parameter rules have a separate limit of %@.",
                            comment: "Rule capacity popover: which rule types count toward which limit",
                            RemoveParamDNRRuleGenerator.maxGeneratedRules.formatted()
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Extension Slots")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                VStack(spacing: 8) {
                    ForEach(targets, id: \.slot) { target in
                        let count = filterManager.ruleCountsByExtension[target.bundleIdentifier] ?? 0
                        let slotFraction = min(Double(count) / Double(ContentBlockerService.safariContentBlockerRuleLimit), 1.0)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(target.displayName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(count.formatted()) / \(ContentBlockerService.safariContentBlockerRuleLimit.formatted())")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(slotFraction > 0.9 ? Color.red : (slotFraction > 0.8 ? Color.orange : Color.secondary))
                            }

                            ruleTypeBar(
                                hiding: filterManager.appliedRuleCounts?.elementHidingByTarget[target.bundleIdentifier] ?? 0,
                                total: count, capacity: ContentBlockerService.safariContentBlockerRuleLimit
                            )
                            .frame(height: 5)
                        }
                    }
                }
            }

            Text("Safari limits each Content Blocker extension to 150,000 rules. wBlock automatically balances and compiles rules across all 5 slots.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Network and element hiding rules in the colors of their Rule Types rows,
    /// so a bar shows what fills it (email feedback).
    private func ruleTypeBar(hiding: Int, total: Int, capacity: Int) -> some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / CGFloat(max(capacity, 1))
            let hidingWidth = CGFloat(min(hiding, total)) * scale
            let usedWidth = min(CGFloat(total) * scale, proxy.size.width)
            // The filled part is its own capsule, so it ends rounded like a
            // progress bar instead of square where element hiding stops.
            HStack(spacing: 0) {
                Rectangle().fill(FilterRulesView.color(for: .network)).frame(width: max(0, usedWidth - hidingWidth))
                Rectangle().fill(FilterRulesView.color(for: .elementHiding)).frame(width: min(hidingWidth, usedWidth))
            }
            .clipShape(Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
    }

    private func ruleTypeRow(_ kind: FilterRuleKind, title: String? = nil, count: Int, limit: Int? = nil) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(FilterRulesView.color(for: kind))
                .frame(width: 8, height: 8)
            Text(title ?? FilterRulesView.title(for: kind))
                .font(.subheadline)
            Spacer()
            Text(limit.map { "\(count.formatted()) / \($0.formatted())" } ?? count.formatted())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private extension View {
    func riskyFilterAlert(_ pending: Binding<RiskyFilterEnable?>) -> some View {
        alert(pending.wrappedValue?.title ?? "", isPresented: Binding(
            get: { pending.wrappedValue != nil },
            set: { if !$0 { pending.wrappedValue = nil } }
        ), presenting: pending.wrappedValue) { filter in
            Button("Cancel", role: .cancel) { pending.wrappedValue = nil }
            Button("Enable") {
                filter.enable()
                pending.wrappedValue = nil
            }
        } message: { filter in
            Text(filter.message)
        }
    }
}
