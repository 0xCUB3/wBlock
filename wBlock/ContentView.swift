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
    @AppStorage("filtersShowEnabledOnly") private var showOnlyEnabledLists = false
    @State private var filterSearchText = ""
    @State private var showFilterSearch = false
    @State private var editingCustomFilter: FilterList?
    @State private var selectedFilterInfo: FilterList?
    @State private var selectedFilterRules: FilterList?
    @State private var selectedCategoryInfo: FilterListCategory?
    @State private var isForeignFiltersExpanded = ProtobufDataManager.shared.isForeignFiltersExpanded
    @State private var showingCapacityPopover = false
    @State private var selectedTab: Int = 0
    @State private var pendingEssentialFilter: FilterList?
    /// Monotonic tokens handed to the Userscripts tab so a ⌘⇧N or ⌘L that
    /// arrives before that tab has been built is still honored on appear.
    @State private var addUserScriptRequest = 0
    @State private var userScriptSearchRequest = 0
    @Environment(\.scenePhase) var scenePhase

    private var hasCompletedOnboarding: Bool {
        dataManager.hasCompletedOnboarding
    }

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

    private var totalSafariRuleCapacity: Int {
        let blockers = ContentBlockerTargetManager.shared.allTargets(forPlatform: filterManager.currentPlatform)
        return blockers.count * ContentBlockerService.safariContentBlockerRuleLimit
    }

    private var shouldShowRuleLimitIndicator: Bool {
        hasAppliedFilters && appliedSafariRulesCount >= totalSafariRuleCapacity
    }

    private var displayableCategories: [FilterListCategory] {
        FilterListCategory.allCases.filter { $0 != .all }
    }

    private var applyChangesSymbolName: String {
        "arrow.triangle.2.circlepath"
    }

    /// Pre-computed filters grouped by category to avoid O(n²) filtering in ForEach
    private var categorizedFilters: [(category: FilterListCategory, filters: [FilterList])] {
        let allFilters = filterManager.filterLists
        let query = filterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [(category: FilterListCategory, filters: [FilterList])] = []

        for category in displayableCategories {
            let filters = allFilters.filter {
                $0.category == category && (!showOnlyEnabledLists || $0.isSelected)
            }
            let searched = query.isEmpty
                ? filters
                : filters.filter { filter in
                    filter.localizedDisplayName.localizedCaseInsensitiveContains(query)
                        || filter.localizedDisplayDescription.localizedCaseInsensitiveContains(query)
                        || filter.url.absoluteString.localizedCaseInsensitiveContains(query)
                }
            if !searched.isEmpty {
                result.append((category: category, filters: searched))
            }
        }

        return result
    }

    /// Invisible zero-size buttons that surface hardware-keyboard shortcuts.
    /// SwiftUI keeps delivering key events to them even though they render
    /// nothing, so the same shortcuts work on macOS and on iOS with an
    /// attached hardware keyboard.
    private var keyboardShortcutHandlers: some View {
        Group {
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

            // macOS gets these from the menu bar (wBlockApp.commands), so the
            // hidden buttons only exist for iPad/iPhone hardware keyboards.
            #if os(iOS)
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
            #endif
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    var body: some View {
        Group {
            #if os(macOS)
            if #available(macOS 26.0, *) {
                nativeTabView
            } else {
                legacyMacTabView
            }
            #else
            nativeTabView
            #endif
        }
        .background(keyboardShortcutHandlers)
        .modifier(
            ContentModifiers(
                filterManager: filterManager,
                userScriptManager: userScriptManager,
                dataManager: dataManager,
                showingAddFilterSheet: $showingAddFilterSheet,
                scenePhase: scenePhase
            ))
        .sheet(item: $editingCustomFilter) { filter in
            if filter.isInlineUserList {
                EditUserListView(filterManager: filterManager, filter: filter)
            } else {
                EditCustomFilterView(filterManager: filterManager, filter: filter)
            }
        }
        .sheet(item: $selectedFilterInfo) { filter in
            FilterInfoView(filter: filter, filterManager: filterManager)
                .infoSheetPresentationCompat()
        }
        .sheet(item: $selectedFilterRules) { filter in
            FilterRulesView(filter: filter)
        }
        .sheet(item: $selectedCategoryInfo) { category in
            FilterCategoryInfoView(
                category: category,
                defaultFilterNames: defaultFilterNames(for: category),
                filterLists: filterManager.filterLists,
                onLanguagesChange: applyRegionalRecommendations,
                onReset: { resetCategory(category) }
            )
        }
        .onChangeCompat(of: selectedTab) { _, _ in
            filterSearchText = ""
            showFilterSearch = false
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
        .alert("Disable Essential Filter?", isPresented: Binding(
            get: { pendingEssentialFilter != nil },
            set: { if !$0 { pendingEssentialFilter = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingEssentialFilter = nil }
            Button("Disable", role: .destructive) {
                if let filter = pendingEssentialFilter {
                    filterManager.setFilterListSelection(id: filter.id, selected: false)
                }
                pendingEssentialFilter = nil
            }
        } message: {
            Text("This recommended filter is part of wBlock’s essential protection. Disabling it may reduce blocking coverage.")
        }
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

    private var nativeTabView: some View {
        TabView(selection: $selectedTab) {
            filtersView
                .tag(0)
                .tabItem { Label("Filters", systemImage: "list.bullet.rectangle") }
            userscriptsView
                .tag(1)
                .tabItem { Label("Userscripts", systemImage: "doc.text.fill") }
            settingsView
                .tag(2)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }

    #if os(macOS)
    private var legacyMacTabView: some View {
        Group {
            switch selectedTab {
            case 1:
                userscriptsView
            case 2:
                settingsView
            default:
                filtersView
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("wBlock", selection: $selectedTab) {
                    Text("Filters").tag(0)
                    Text("Userscripts").tag(1)
                    Text("Settings").tag(2)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
        }
    }
    #endif

    private func applyPendingChanges() {
        guard !filterManager.isLoading else { return }
        filterManager.applyOrCheckForUpdates()
    }

    private var applyChangesToolbarButton: some View {
        ApplyChangesHoldButton(
            isDisabled: filterManager.isLoading,
            hasPendingChanges: hasPendingChanges,
            onTap: applyPendingChanges,
            onForceApply: { filterManager.forceApplyChanges() }
        ) {
            if hasPendingChanges {
                Text("Apply")
                    .fontWeight(.semibold)
            } else {
                Image(systemName: applyChangesSymbolName)
            }
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
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        applyChangesToolbarButton
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if #unavailable(iOS 26.0) {
                            Button {
                                showFilterSearch = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        Button {
                            showingAddFilterSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        Button {
                            showOnlyEnabledLists.toggle()
                        } label: {
                            Image(
                                systemName: showOnlyEnabledLists
                                    ? "line.3.horizontal.decrease.circle.fill"
                                    : "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            #endif
        }
        #if os(iOS)
            .searchableCompat(
                text: $filterSearchText,
                isPresented: $showFilterSearch,
                prompt: "Search filters"
            )
            .modifier(SearchMinimizeBehavior())
        #endif
        #if os(macOS)
            .frame(
                minWidth: 480, idealWidth: 540, maxWidth: .infinity,
                minHeight: 550, idealHeight: 720, maxHeight: .infinity
            )
            .modifier(macFiltersToolbar)
        #endif
    }

    #if os(macOS)
    private var macFiltersToolbar: some ViewModifier {
        MacActionsToolbar(isSearchExpanded: showFilterSearch) {
            Button {
                showingAddFilterSheet = true
            } label: {
                Label("Add Filter", systemImage: "plus")
            }
            applyChangesToolbarButton
        } filter: {
            Button {
                showOnlyEnabledLists.toggle()
            } label: {
                Label(
                    "Show Enabled Only",
                    systemImage: showOnlyEnabledLists
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
            }
        } search: {
            ToolbarSearchField(
                text: $filterSearchText,
                isExpanded: $showFilterSearch,
                prompt: "Search filters"
            )
        }
    }
    #endif

    private var nativeFiltersListView: some View {
        #if os(iOS)
        List {
            Section {
                statsCardsView
                    .unifiedTabCardSectionRow()
            }

            ForEach(categorizedFilters, id: \.category) { item in
                if item.category == .foreign {
                    Section {
                        DisclosureGroup(isExpanded: $isForeignFiltersExpanded) {
                            ForEach(ForeignFilterOrganizer.groups(for: item.filters)) { group in
                                foreignFilterGroupHeader(group.title)
                                ForEach(group.filters) { filter in
                                    filterRowView(for: filter, showsFlags: false)
                                }
                            }
                        } label: {
                            categoryHeader(item.category)
                        }
                    }
                } else {
                    Section {
                        ForEach(item.filters) { filter in
                            filterRowView(for: filter)
                        }
                    } header: {
                        categoryHeader(item.category)
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
        ScrollView {
            // Everything here is eager. LazyVStack hung the window on scroll (#172,
            // #632) and, when nested, reported shifting estimated heights that made
            // the scrollbar jump and left blank regional rows (#601, #602).
            VStack(spacing: 20) {
                statsCardsView

                VStack(spacing: 16) {
                    ForEach(categorizedFilters, id: \.category) { item in
                        if item.category == .foreign {
                            macOSForeignFiltersView(filters: item.filters)
                        } else {
                            macOSFilterSectionView(category: item.category, filters: item.filters)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .id("\(showOnlyEnabledLists)-\(filterSearchText)")
        #endif
    }

    private var userscriptsView: some View {
        CompatibleNavigationStack(requiresNavigationView: false) {
            UserScriptManagerView(
                userScriptManager: userScriptManager,
                hasPendingChanges: hasPendingChanges,
                isApplyingChanges: filterManager.isLoading,
                onApplyChanges: applyPendingChanges,
                onForceApplyChanges: { filterManager.forceApplyChanges() },
                tabSelection: selectedTab,
                addRequest: addUserScriptRequest,
                searchRequest: userScriptSearchRequest,
                onRefresh: {
                    guard !filterManager.isLoading else { return }
                    await filterManager.checkForUpdates(scope: .scripts, presentation: .refresh)
                }
            )
                .safeAreaInset(edge: .top) {
                    if filterManager.isBlockingPaused {
                        pauseBlockingBanner
                    }
                }
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            applyChangesToolbarButton
                        }
                    }
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
        HStack(spacing: 12) {
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
                    valueColor: enabledListsCount == 0 ? .secondary : (hasAppliedFilters ? .primary : .secondary)
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
            #if os(macOS)
            .popover(isPresented: $showingCapacityPopover, arrowEdge: .top) {
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
        .padding(.horizontal)
    }

    private func categoryHeader(_ category: FilterListCategory) -> some View {
        HStack(spacing: 6) {
            Text(category.localizedName)
                .foregroundStyle(.primary)
                .textCase(.none)
            Button {
                selectedCategoryInfo = category
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Info")
        }
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

    private func foreignFilterGroupHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 6)
    }

    private func filterRowView(for filter: FilterList, showsFlags: Bool = true) -> some View {
        FilterRowView(
            filter: filter,
            showsFlags: showsFlags,
            onInfo: { selectedFilterInfo = filter },
            onViewRules: { selectedFilterRules = filter },
            onEdit: { editingCustomFilter = filter },
            onDelete: { filterManager.removeFilterList(filter) },
            onToggle: { newValue in
                if !newValue && FilterListLoader.essentialFilterNames.contains(filter.name) {
                    pendingEssentialFilter = filter
                } else {
                    filterManager.setFilterListSelection(id: filter.id, selected: newValue)
                }
            }
        )
    }

    #if os(macOS)
    private func macOSFilterSectionView(category: FilterListCategory, filters: [FilterList]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                categoryHeader(category)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(filters) { filter in
                    filterRowView(for: filter)
                    if filter.id != filters.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func macOSForeignFiltersView(filters: [FilterList]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $isForeignFiltersExpanded) {
                VStack(spacing: 0) {
                    ForEach(ForeignFilterOrganizer.groups(for: filters)) { group in
                        HStack {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        ForEach(group.filters) { filter in
                            filterRowView(for: filter, showsFlags: false)
                            if filter.id != group.filters.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } label: {
                categoryHeader(.foreign)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 4)
        }
    }
    #endif
}

struct FilterRowView: View {
    let filter: FilterList
    let showsFlags: Bool
    var onInfo: () -> Void
    var onViewRules: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onToggle: (Bool) -> Void

    @ViewBuilder
    private var contextMenuItems: some View {
        let actions = ContextMenuActionAvailability.filterActions(for: filter)
        if actions.contains(.info) {
            Button {
                onInfo()
            } label: {
                Label("Info", systemImage: "info.circle")
            }
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
        if actions.contains(.deleteList) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Added List", systemImage: "trash")
            }
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // The info tap lives on the text column only. A row-wide tap gesture
            // competes with the switch on iOS 17, where the gesture wins and a tap
            // on the switch opens the info sheet instead of toggling the filter.
            filterDetails
                .contentShape(.interaction, Rectangle())
                .onTapGesture {
                    // Defer to avoid race with context menu dismissal on iOS
                    DispatchQueue.main.async {
                        onInfo()
                    }
                }
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
            .frame(alignment: .center)
        }
        .contextMenu {
            contextMenuItems
        }
        #if os(macOS)
        .padding(16)
        #endif
    }

    private var filterDetails: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if showsFlags, let flags = filter.flagEmojis {
                        Text(flags)
                    }
                    Text(filter.localizedDisplayName)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if filter.isInlineUserList {
                        Text("Local Import")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    } else if filter.isCustom {
                        Text("Custom")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                .font(.body)

                if filter.isCustom && !filter.isInlineUserList && filter.sourceRuleCount == nil {
                    Text("Not Downloaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let rawCount = filter.rawSourceRuleCount,
                   let expandedCount = filter.sourceRuleCount,
                   rawCount != expandedCount {
                    // Both counts available and different — show expansion
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString(
                                "(%@ source → %@ expanded rules)",
                                comment: "Filter rule expansion summary"
                            ),
                            rawCount.formatted(),
                            expandedCount.formatted()
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let count = filter.sourceRuleCount, count > 0 {
                    // Single count (no expansion, counts match, or rawSourceRuleCount is nil after restart)
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("(%@ rules)", comment: "Filter rule count summary"),
                            count.formatted()
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !filter.localizedDisplayDescription.isEmpty {
                    Text(filter.localizedDisplayDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 4) {
                    if !filter.version.isEmpty {
                        Text(
                            LocalizedStrings.format(
                                "Version %@",
                                comment: "Filter version label",
                                filter.version
                            )
                        )
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }

                    if let lastUpdatedFormatted = filter.lastUpdatedFormatted {
                        if !filter.version.isEmpty {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                        Text(lastUpdatedFormatted)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }
}

#if os(iOS)
private struct OnboardingPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let filterManager: AppFilterManager

    @ViewBuilder
    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.sheet(isPresented: $isPresented) {
                OnboardingView(filterManager: filterManager)
            }
        } else {
            content.fullScreenCover(isPresented: $isPresented) {
                OnboardingView(filterManager: filterManager)
            }
        }
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

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingAddFilterSheet) {
                AddFilterListView(filterManager: filterManager)
            }
            .sheet(isPresented: $filterManager.showingApplyProgressSheet) {
                ApplyChangesProgressView(
                    filterManager: filterManager,
                    viewModel: filterManager.applyProgressViewModel,
                    isPresented: $filterManager.showingApplyProgressSheet
                )
            }
            #if os(iOS)
            // A modal alert for "nothing to do" is one tap too many on a phone;
            // show a toast that any touch (or three seconds) clears.
            .overlay(alignment: .top) {
                if filterManager.showingNoUpdatesAlert {
                    NoUpdatesToast { filterManager.showingNoUpdatesAlert = false }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: filterManager.showingNoUpdatesAlert)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if filterManager.showingNoUpdatesAlert {
                        filterManager.showingNoUpdatesAlert = false
                    }
                },
                including: filterManager.showingNoUpdatesAlert ? .all : .subviews
            )
            #else
            .alert("No Updates Found", isPresented: $filterManager.showingNoUpdatesAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You're already using the latest filters.")
            }
            #endif
            .alert(
                filterManager.ruleLimitWarningTitle,
                isPresented: $filterManager.showingRuleLimitWarningAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(filterManager.ruleLimitWarningMessage)
            }
            .alert("Filters Auto-Disabled", isPresented: $filterManager.showingAutoDisabledAlert) {
                Button("OK", role: .cancel) {}
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
            .overlay {
                if filterManager.isLoading && !filterManager.showingApplyProgressSheet
                    && !filterManager.suppressBlockingOverlay
                {
                    ZStack {
                        Color.black.opacity(0.1).ignoresSafeArea()
                        VStack {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text(filterManager.statusDescription)
                                .padding(.top, 10)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 10)
                    }
                }
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
                    filterManager: filterManager
                ))
            #elseif os(macOS)
                .sheet(isPresented: $showOnboardingSheet) {
                    OnboardingView(filterManager: filterManager)
                }
            #endif
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

private extension FilterListCategory {
    static var userListCategories: [FilterListCategory] {
        [.custom] + allCases.filter { $0 != .all && $0 != .custom && $0 != .scripts }
    }
}

private func userListCategoryPicker(selection: Binding<FilterListCategory>) -> some View {
    Picker("Category", selection: selection) {
        ForEach(FilterListCategory.userListCategories) { category in
            Text(category.localizedName).tag(category)
        }
    }
    .pickerStyle(.menu)
}


enum FilterListAddValidationMode {
    case url
    case text
    case file
}

struct FilterListAddValidation {
    static func isDuplicateName(
        candidate: String,
        mode: FilterListAddValidationMode,
        urlCount: Int,
        existingNames: [String]
    ) -> Bool {
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCandidate.isEmpty else { return false }
        guard mode != .url || urlCount <= 1 else { return false }
        return existingNames.contains {
            $0.caseInsensitiveCompare(trimmedCandidate) == .orderedSame
        }
    }
}

struct AddFilterListView: View {
    @ObservedObject var filterManager: AppFilterManager

	@Environment(\.dismiss) private var dismiss
	@FocusState private var urlFieldIsFocused: Bool

    @State private var urlInput: String = ""
    @State private var customName: String = ""
    @State private var isNameSectionExpanded: Bool = false
    @State private var isSaving: Bool = false
    @State private var showingFileImporter = false
    @State private var importErrorMessage: String?
    @State private var pastedRules: String = ""
    @State private var isShowingRulesEditor = false
    @StateObject private var rulesEditorController = CodeMirrorEditorController(text: "")
    @State private var userListTitle: String = ""
    @State private var userListDescription: String = ""
    @State private var selectedCategory: FilterListCategory = .custom
    @State private var stagedFile: StagedFilterFile?
    @State private var isStagingFile = false
    @State private var stagingGeneration = 0

    private struct StagedFilterFile {
        let filename: String
        let content: String
    }

    private enum AddMode: String, CaseIterable, Identifiable, AddContentMode {
        case url = "URL"
        case paste = "Text"
        case file = "File"

        var id: String { rawValue }
        var localizedTitle: LocalizedStringKey { LocalizedStringKey(rawValue) }
        var systemImage: String {
            switch self {
            case .url: return "link"
            case .paste: return "text.alignleft"
            case .file: return "doc"
            }
        }
    }

    @State private var addMode: AddMode = .url


    private var parsedURLInput: FilterListURLParseResult {
        FilterListURLSupport.parseRemoteURLs(from: urlInput)
    }

    private var newURLs: [URL] {
        let existingURLs = Set(filterManager.filterLists.map(\.url))
        return parsedURLInput.urls.filter { !existingURLs.contains($0) }
    }

    private var existingURLCount: Int {
        parsedURLInput.urls.count - newURLs.count
    }

    private var validationState: ValidationState {
        validationState(for: urlInput)
    }

		var body: some View {
		    Group {
		        #if os(iOS)
		            CompatibleNavigationStack {
		                addTabs
		                    .navigationTitle("Add Filter List")
		                    .navigationBarTitleDisplayMode(.inline)
		                    .toolbar {
		                        ToolbarItem(placement: .cancellationAction) {
		                            Button("Cancel") { dismiss() }
		                                .disabled(isSaving)
		                        }
		                        ToolbarItem(placement: .confirmationAction) {
		                            Button(action: submit) {
		                                if isSaving {
		                                    ProgressView()
		                                } else {
		                                    Text(LocalizedStringKey(addButtonTitle))
		                                }
		                            }
		                            .disabled(!canSubmit || isSaving)
		                        }
		                    }
		            }
		            .interactiveDismissDisabled(isSaving)
		            .largeSheetPresentationCompat()
	        #elseif os(macOS)
	            macosBody
	        #endif
	    }
        .onChangeCompat(of: urlInput) { oldValue, newValue in
            let normalized = FilterListURLSupport.normalizeURLInput(from: oldValue, to: newValue)
            if normalized != newValue {
                urlInput = normalized
            }
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
            CodeEditorSheet(
                editorController: rulesEditorController,
                onTextChanged: { pastedRules = $0 },
                onPaste: {
                    pasteRulesFromClipboard()
                    rulesEditorController.replaceText(pastedRules, markClean: true)
                }
            )
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: filterImportTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                stageFile(at: url)
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

	    #if os(macOS)
	        private var macosBody: some View {
	            SheetContainer {
	                SheetHeader(title: "Add Filter List", isLoading: isSaving) {
	                    dismiss()
	                }

	                ScrollView {
	                    VStack(alignment: .leading, spacing: 16) {
	                        modePickerCard
	                        macosModeContent
	                    }
	                    .padding(.horizontal, SheetDesign.contentHorizontalPadding)
	                    .padding(.top, 12)
	                    .padding(.bottom, 40)
	                }

	                SheetBottomToolbar {
	                    Spacer()
	                    macosAddButton
	                }
	            }
	            .interactiveDismissDisabled(isSaving)
	            .frame(minWidth: 560, minHeight: addMode == .paste ? 620 : 520)
	        }

	        private var macosAddButton: some View {
	            Button(action: submit) {
	                HStack(spacing: 8) {
	                    if isSaving {
	                        ProgressView()
	                            .scaleEffect(0.9)
	                    }
	                    Text(LocalizedStringKey(isSaving ? "Adding…" : addButtonTitle))
	                        .fontWeight(.semibold)
	                }
	            }
	            .primaryActionButtonStyle()
	            .disabled(!canSubmit || isSaving)
	            .keyboardShortcut(.defaultAction)
	        }

	        private var modePickerCard: some View {
	            AddContentModePicker(selection: $addMode)
	        }

	        @ViewBuilder
	        private var macosModeContent: some View {
	            switch addMode {
	            case .url:
	                VStack(alignment: .leading, spacing: 16) {
	                    macosURLCard
	                    filterRequirementsPanel
	                }
	            case .paste:
	                macosPasteCard
	            case .file:
	                macosFileCard
	            }
	        }

	        private var macosURLCard: some View {
	            VStack(alignment: .leading, spacing: 12) {
	                VStack(alignment: .leading, spacing: 6) {
	                    Text("URLs")
	                        .font(.caption)
	                        .foregroundStyle(.secondary)

	                    urlInputEditor
	                }

                    if newURLs.count <= 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Title (optional)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField("Title", text: $customName)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                        }
                    } else {
                        Text("Titles will be created from each URL.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Category")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        userListCategoryPicker(selection: $selectedCategory)
                            .labelsHidden()
                    }

	                urlFooterMessage
	            }
	            .padding(16)
	            .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
	        }

	        private var macosPasteCard: some View {
	            VStack(alignment: .leading, spacing: 12) {
	                userListMetaFields

	                VStack(alignment: .leading, spacing: 6) {
	                    Text("Rules")
	                        .font(.caption)
	                        .foregroundStyle(.secondary)

                    SyntaxHighlightingTextView(text: $pastedRules)
                        .frame(minHeight: 260)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.quaternary, lineWidth: 1)
                        )
                    pasteRulesButton
	                }
                filterTextRequirementsPanel
	            }
	            .padding(16)
	            .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
	        }

	        private var macosFileCard: some View {
	            VStack(alignment: .leading, spacing: 12) {
                    fileSelectionButton
                    if stagedFile != nil {
                        userListMetaFields
                    }
                    filterFileRequirementsPanel
	            }
	            .padding(16)
	            .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
	        }

        private var fileSelectionButton: some View {
            Button {
                showingFileImporter = true
                importErrorMessage = nil
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc")
                    Text(stagedFile?.filename ?? "Choose File")
                    if isStagingFile { ProgressView().controlSize(.small) }
                    Spacer()
                    if stagedFile != nil {
                        Text("Change File")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
	    #endif

        #if os(iOS)
        private var fileSelectionButton: some View {
            Button {
                showingFileImporter = true
                importErrorMessage = nil
            } label: {
                HStack {
                    Image(systemName: "doc")
                    Text(stagedFile?.filename ?? "Choose File")
                    if isStagingFile { ProgressView().controlSize(.small) }
                    Spacer()
                    if stagedFile != nil {
                        Text("Change File").foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isSaving)
        }
        #endif

	    private var addTabs: some View {
	        TabView(selection: $addMode) {
	            urlTab
	                .tag(AddMode.url)
	                .tabItem { Label("URL", systemImage: "link") }

	            pasteTab
	                .tag(AddMode.paste)
	                .tabItem { Label("Text", systemImage: "text.alignleft") }

	            fileTab
	                .tag(AddMode.file)
	                .tabItem { Label("File", systemImage: "doc") }
	        }
	    }

		    private var urlTab: some View {
		        Form {
		            Section {
		                VStack(alignment: .leading, spacing: 6) {
                        Text("URLs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        urlInputEditor
                    }

                    if newURLs.count <= 1 {
                        TextField("Title (optional)", text: $customName)
                            #if os(iOS)
                                .textInputAutocapitalization(.words)
                            #endif
                    } else {
                        Text("Titles will be created from each URL.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    userListCategoryPicker(selection: $selectedCategory)
		            } footer: {
		                urlFooterMessage
		            }
		        }
		    }

		    private var pasteTab: some View {
		        Form {
		            Section {
		            TextField("Title", text: $userListTitle)
		                    #if os(iOS)
		                .textInputAutocapitalization(.words)
		            #endif
		                    .autocorrectionDisabled()
	                TextField("Description", text: $userListDescription)
	                    #if os(iOS)
	                        .textInputAutocapitalization(.sentences)
	                    #endif
	                    .autocorrectionDisabled()
                userListCategoryPicker(selection: $selectedCategory)
	            }

            Section("Rules") {
                SyntaxHighlightingTextView(text: $pastedRules)
                    .frame(minHeight: 220)
                HStack(spacing: 10) {
                    pasteRulesButton
                    Button {
                        rulesEditorController.replaceText(pastedRules, markClean: true)
                        isShowingRulesEditor = true
                    } label: {
                        Label("Use Editor", systemImage: "curlybraces")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                }
            }
            Section {
                filterTextRequirementsPanel
            }
        }
    }

		    private var fileTab: some View {
                Form {
                    Section {
                        fileSelectionButton
                        if stagedFile != nil {
                            TextField("Name", text: $userListTitle)
                                #if os(iOS)
                                .textInputAutocapitalization(.words)
                                #endif
                                .autocorrectionDisabled()
                            TextField("Description", text: $userListDescription)
                                #if os(iOS)
                                .textInputAutocapitalization(.sentences)
                                #endif
                                .autocorrectionDisabled()
                            userListCategoryPicker(selection: $selectedCategory)
                        }
                    }
                    Section {
                        filterFileRequirementsPanel
                    } footer: {
                        if let importErrorMessage {
                            Text(importErrorMessage).foregroundStyle(.orange)
                        }
                    }
                }
            }

    private var pasteRulesButton: some View {
        Button(action: pasteRulesFromClipboard) {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        .buttonStyle(.bordered)
        .disabled(isSaving)
    }

    private var filterTextRequirementsPanel: some View {
        AddContentRequirementsPanel(requirements: [
            AddContentRequirement(systemImage: "character.cursor.ibeam", text: "Title is required."),
            AddContentRequirement(systemImage: "checkmark.circle", text: "Rules")
        ])
    }

    private var filterFileRequirementsPanel: some View {
        AddContentRequirementsPanel(requirements: [
            AddContentRequirement(systemImage: "doc", text: "Choose File"),
            AddContentRequirement(systemImage: "character.cursor.ibeam", text: "Title is required."),
            AddContentRequirement(systemImage: "checkmark.circle", text: "That doesn't look like a filter list.")
        ])
    }

	    private var filterRequirementsPanel: some View {
        AddContentRequirementsPanel(
            requirements: [
                AddContentRequirement(systemImage: "link", text: "Use a valid http:// or https:// URL"),
                AddContentRequirement(systemImage: "globe", text: "Include a host name"),
                AddContentRequirement(systemImage: "checkmark.circle", text: "Do not use a userscript URL ending in .js, .mjs, or .cjs")
            ],
            footer: "wBlock will fetch and enable the filter list automatically"
        )
    }

	    private var urlInputEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $urlInput)
                .font(.body)
                .autocorrectionDisabled()
                .focused($urlFieldIsFocused)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif

            if urlInput.isEmpty {
                // Match TextEditor's own text container insets so the placeholder
                // sits on the same line as the caret and typed text (#609).
                Text("Paste one or more filter URLs, one per line.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    #if os(macOS)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    #else
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    #endif
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 64, maxHeight: 96)
        .background(.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
        .accessibilityLabel("URLs")
    }

    // MARK: - Footer
	    private var urlFooterMessage: some View {
	        Group {
	            if isCustomNameDuplicate {
	                Text("That name is already used by another filter list.")
	                    .foregroundStyle(.orange)
	            } else {
	                switch validationState {
	                case .idle:
	                    EmptyView()
	                case .invalid:
                        if let lineNumber = parsedURLInput.invalidLineNumbers.first {
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
            return !userListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !pastedRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file:
            return !isStagingFile
                && stagedFile != nil
                && !userListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submit() {
        switch addMode {
        case .url:
            guard case .valid(let urls) = validationState else { return }
            isSaving = true
            Task { @MainActor in
                let allowsCustomName = urls.count == 1
                let userProvidedName = allowsCustomName && !trimmedCustomName.isEmpty
                for url in urls {
                    let finalName = userProvidedName ? trimmedCustomName : defaultName(for: url)
                    filterManager.addFilterList(
                        name: finalName,
                        urlString: url.absoluteString,
                        category: selectedCategory,
                        hasUserProvidedName: userProvidedName
                    )
                }
                isSaving = false
                dismiss()
            }
        case .paste:
            isSaving = true
            Task { @MainActor in
                let finalName = userListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalDescription = userListDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalRules = pastedRules.trimmingCharacters(in: .whitespacesAndNewlines)
                filterManager.addUserList(
                    name: finalName,
                    description: finalDescription.isEmpty ? nil : finalDescription,
                    content: finalRules,
                    category: selectedCategory,
                    isSelected: true
                )
                isSaving = false
                if !filterManager.hasError {
                    dismiss()
                } else {
                    importErrorMessage = filterManager.statusDescription
                }
            }
        case .file:
            guard let stagedFile else { return }
            isSaving = true
            Task { @MainActor in
                let finalName = userListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalDescription = userListDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                filterManager.addUserList(
                    name: finalName,
                    description: finalDescription.isEmpty ? nil : finalDescription,
                    content: stagedFile.content,
                    category: selectedCategory,
                    isSelected: true
                )
                isSaving = false
                if !filterManager.hasError {
                    dismiss()
                } else {
                    importErrorMessage = filterManager.statusDescription
                }
            }
        }
    }

    private var addButtonTitle: String {
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
        }
    }

    private var userListMetaFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Name", text: $userListTitle)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.words)
                    #endif
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Description", text: $userListDescription)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                    #endif
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Category")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                userListCategoryPicker(selection: $selectedCategory)
                    .labelsHidden()
            }
    }
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
                    let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedContent.isEmpty,
                          FilterListContentValidator.appearsToBeFilterList(trimmedContent)
                    else {
                        throw NSError(domain: "wBlock.filterImport", code: 1, userInfo: [
                            NSLocalizedDescriptionKey: LocalizedStrings.text(
                                "That doesn't look like a filter list.",
                                comment: "User list validation error"
                            )
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

    private var trimmedCustomName: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isCustomNameDuplicate: Bool {
        FilterListAddValidation.isDuplicateName(
            candidate: duplicateNameCandidate,
            mode: validationMode,
            urlCount: newURLs.count,
            existingNames: filterManager.filterLists.map(\.name)
        )
    }

    private var duplicateNameCandidate: String {
        switch addMode {
        case .url: return customName
        case .paste, .file: return userListTitle
        }
    }

    private var validationMode: FilterListAddValidationMode {
        switch addMode {
        case .url: return .url
        case .paste: return .text
        case .file: return .file
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
    @State private var selectedCategory: FilterListCategory
    @State private var errorMessage: String?

    init(filterManager: AppFilterManager, filter: FilterList) {
        self.filterManager = filterManager
        self.filter = filter
        self._name = State(initialValue: filter.name)
        self._selectedCategory = State(initialValue: filter.category)
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

                            userListCategoryPicker(selection: $selectedCategory)

                            Text(filter.url.absoluteString)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
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

                                Text("Category")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                userListCategoryPicker(selection: $selectedCategory)
                                    .labelsHidden()

                                Text(filter.url.absoluteString)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)

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
            category: selectedCategory
        ) {
            dismiss()
        } else {
            errorMessage = filterManager.statusDescription
        }
    }
}

struct EditUserListView: View {
    @ObservedObject var filterManager: AppFilterManager
    let filter: FilterList

    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFieldIsFocused: Bool

    @State private var title: String
    @State private var description: String
    @State private var selectedCategory: FilterListCategory
    @State private var rules: String = ""
    @State private var isLoadingContent: Bool = true
    @State private var errorMessage: String?
    @State private var isShowingEditor = false
    @StateObject private var editorController = CodeMirrorEditorController(text: "")

    init(filterManager: AppFilterManager, filter: FilterList) {
        self.filterManager = filterManager
        self.filter = filter
        self._title = State(initialValue: filter.name)
        self._description = State(initialValue: filter.description == "User list." ? "" : filter.description)
        self._selectedCategory = State(initialValue: filter.category)
    }

    var body: some View {
        Group {
            #if os(iOS)
                CompatibleNavigationStack {
                    Form {
                        Section {
                            TextField("Title", text: $title)
                                .focused($titleFieldIsFocused)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()

                            TextField("Description", text: $description)
                                .textInputAutocapitalization(.sentences)
                                .autocorrectionDisabled()

                            userListCategoryPicker(selection: $selectedCategory)
                        } footer: {
                            if isDuplicateTitle {
                                Text("That title is already used by another filter list.")
                                    .foregroundStyle(.orange)
                            }
                        }

                        Section("Rules") {
                            SyntaxHighlightingTextView(text: $rules)
                                .frame(minHeight: 260)
                            useEditorButton
                        }
                    }
                    .navigationTitle("Edit User List")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                                .disabled(isLoadingContent)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { save() }
                                .disabled(!canSave)
                        }
                        ToolbarItem(placement: .principal) {
                            if isLoadingContent {
                                ProgressView()
                            }
                        }
                    }
                }
                .interactiveDismissDisabled(isLoadingContent)
                .onAppear {
                    titleFieldIsFocused = true
                    loadContent()
                }
                .alert(
                    "Couldn’t Save",
                    isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { _ in errorMessage = nil }
                    )
                ) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
                .largeSheetPresentationCompat()
            #else
                SheetContainer {
                    SheetHeader(title: "Edit User List", isLoading: isLoadingContent) {
                        dismiss()
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Title")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                TextField("User List", text: $title)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($titleFieldIsFocused)
                                    .autocorrectionDisabled()
                                    .onSubmit {
                                        titleFieldIsFocused = false
                                    }

                                Text("Description")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                TextField("Description", text: $description)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()

                                Text("Category")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                userListCategoryPicker(selection: $selectedCategory)
                                    .labelsHidden()

                                Text(filter.url.absoluteString)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                                    .textSelection(.enabled)

                                if isDuplicateTitle {
                                    Text("That title is already used by another filter list.")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Rules")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    useEditorButton
                                        .controlSize(.small)
                                }

                                SyntaxHighlightingTextView(text: $rules)
                                    .frame(minHeight: 260)
                                    .padding(10)
                                    .background(
                                        .background,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(.quaternary, lineWidth: 1)
                                    )
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
                .interactiveDismissDisabled(isLoadingContent)
                .onAppear {
                    titleFieldIsFocused = true
                    loadContent()
                }
                .alert(
                    "Couldn’t Save",
                    isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { _ in errorMessage = nil }
                    )
                ) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
            #endif
        }
        .sheet(isPresented: $isShowingEditor) {
            CodeEditorSheet(
                editorController: editorController,
                onTextChanged: { rules = $0 },
                onPaste: pasteRulesIntoEditor
            )
        }
    }

    private var useEditorButton: some View {
        Button {
            editorController.replaceText(rules, markClean: true)
            isShowingEditor = true
        } label: {
            Label("Use Editor", systemImage: "curlybraces")
        }
        .disabled(isLoadingContent)
    }

    private func pasteRulesIntoEditor() {
        #if os(iOS)
        guard let string = UIPasteboard.general.string else { return }
        #else
        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        #endif
        editorController.replaceText(string, markClean: true)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRules: String {
        rules.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicateTitle: Bool {
        let candidate = trimmedTitle
        guard !candidate.isEmpty else { return false }
        return filterManager.filterLists.contains(where: {
            $0.id != filter.id && $0.name.caseInsensitiveCompare(candidate) == .orderedSame
        })
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && !trimmedRules.isEmpty && !isDuplicateTitle && !isLoadingContent
    }

    private var saveButton: some View {
        Button("Save") {
            save()
        }
        .primaryActionButtonStyle()
        .disabled(!canSave)
        .keyboardShortcut(.defaultAction)
    }

    private func loadContent() {
        isLoadingContent = true
        Task {
            let loadedRules = await Task.detached { () -> String? in
                guard let containerURL = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value
                ),
                let fileURL = ContentBlockerIncrementalCache.existingLocalFileURL(
                    for: filter,
                    containerURL: containerURL
                ) else { return nil }
                return try? String(contentsOf: fileURL, encoding: .utf8)
            }.value

            await MainActor.run {
                rules = loadedRules ?? ""
                isLoadingContent = false
            }
        }
    }

    private func save() {
        filterManager.updateUserList(
            id: filter.id,
            name: trimmedTitle,
            description: description,
            category: selectedCategory,
            content: trimmedRules
        )
        if filterManager.hasError {
            errorMessage = filterManager.statusDescription
        } else {
            dismiss()
        }
    }
}

#if os(iOS)
/// Non-blocking replacement for the "No Updates Found" alert on iOS.
struct NoUpdatesToast: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("No Updates Found")
                    .font(.subheadline.weight(.semibold))
                Text("You're already using the latest filters.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            dismiss()
        }
    }
}
#endif

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
        targets.count * ContentBlockerService.safariContentBlockerRuleLimit
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
        totalCapacity > 0 ? min(Double(totalUsed) / Double(totalCapacity), 1.0) : 0.0
    }

    var body: some View {
        #if os(macOS)
        capacityContent
            .padding(16)
            .frame(width: 340)
        #else
        capacitySheetContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .largeSheetPresentationCompat()
            .fittedFormSheetSizingCompat()
        #endif
    }

    #if !os(macOS)
    private var capacityColumn: some View {
        capacityContent
            .padding(20)
            .frame(maxWidth: 380, alignment: .leading)
            .frame(maxWidth: .infinity)
    }

    /// A landscape sheet is far wider than the 380pt column, so an indicator
    /// would sit detached from the content: scroll only when it cannot fit.
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
                    Text("\(totalUsed.formatted()) / \(totalCapacity.formatted()) rules (\(Int(overallFraction * 100))%)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(overallFraction > 0.8 ? Color.orange : Color.blue)
                        .scaleEffect(x: max(0, overallFraction), y: 1, anchor: .leading)
                }
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

                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.12))
                                Capsule()
                                    .fill(slotFraction > 0.9 ? Color.red : (slotFraction > 0.8 ? Color.orange : Color.accentColor))
                                    .scaleEffect(x: max(0, slotFraction), y: 1, anchor: .leading)
                            }
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
}
