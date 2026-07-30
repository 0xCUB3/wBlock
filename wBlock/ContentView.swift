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
    @State private var isForeignFiltersExpanded = ProtobufDataManager.shared.isForeignFiltersExpanded
    @State private var showingCapacityPopover = false
    @State private var selectedTab: Int = 0
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
        return blockers.count * 150_000
    }

    private var isApproachingTotalSafariRuleCapacity: Bool {
        guard hasAppliedFilters else { return false }
        let warningThreshold = Int(Double(totalSafariRuleCapacity) * 0.8)
        return appliedSafariRulesCount >= warningThreshold
    }

    private var shouldShowRuleLimitIndicator: Bool {
        isApproachingTotalSafariRuleCapacity || !filterManager.extensionsApproachingLimit.isEmpty
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

    var body: some View {
        TabView(selection: $selectedTab) {
            filtersView
                .tag(0)
                .tabItem {
                    Label("Filters", systemImage: "list.bullet.rectangle")
                }
            userscriptsView
                .tag(1)
                .tabItem {
                    Label("Userscripts", systemImage: "doc.text.fill")
                }
            settingsView
                .tag(2)
                .tabItem {
                    Label("Settings", systemImage: "gear")
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
            if isInlineUserList(filter) {
                EditUserListView(filterManager: filterManager, filter: filter)
            } else {
                EditCustomFilterView(filterManager: filterManager, filter: filter)
            }
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

    private func isInlineUserList(_ filter: FilterList) -> Bool {
        filter.isInlineUserList
    }

    private func supportsCustomActions(_ filter: FilterList) -> Bool {
        filter.isCustom
    }

    private func applyPendingChanges() {
        guard !filterManager.isLoading else { return }
        filterManager.checkAndEnableFilters(forceReload: true)
    }

    private var applyChangesToolbarButton: some View {
        Button {
            applyPendingChanges()
        } label: {
            if hasPendingChanges {
                Text("Apply")
                    .fontWeight(.semibold)
            } else {
                Image(systemName: applyChangesSymbolName)
            }
        }
        .disabled(filterManager.isLoading)
        .accessibilityLabel("Apply Changes")
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
        #else
            .searchable(text: $filterSearchText, prompt: "Search filters")
            .frame(
                minWidth: 480, idealWidth: 540, maxWidth: .infinity,
                minHeight: 550, idealHeight: 720, maxHeight: .infinity
            )
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    applyChangesToolbarButton
                        .help(
                            hasPendingChanges
                                ? String(localized: "Apply your pending changes")
                                : String(localized: "Apply changes")
                        )

                    Button {
                        showingAddFilterSheet = true
                    } label: {
                        Label("Add Filter", systemImage: "plus")
                    }
                    Button {
                        showOnlyEnabledLists.toggle()
                    } label: {
                        Label(
                            "Show Enabled Only",
                            systemImage: showOnlyEnabledLists
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle")
                    }
                }
            }
        #endif
    }

    private var nativeFiltersListView: some View {
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
                                    filterRowView(for: filter)
                                }
                            }
                        } label: {
                            Text(item.category.localizedName)
                        }
                    }
                } else {
                    Section(item.category.localizedName) {
                        ForEach(item.filters) { filter in
                            filterRowView(for: filter)
                        }
                    }
                }
            }
        }
        .unifiedTabListStyle()
        .refreshable {
            guard !filterManager.isLoading else { return }
            await filterManager.checkForUpdates()
        }
    }

    private var userscriptsView: some View {
        CompatibleNavigationStack(requiresNavigationView: false) {
            UserScriptManagerView(
                userScriptManager: userScriptManager,
                hasPendingChanges: hasPendingChanges,
                isApplyingChanges: filterManager.isLoading,
                onApplyChanges: applyPendingChanges
            )
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
                Text("Blocking is paused. Tap Resume to re-enable all blocking.")
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
                        return "Rules"
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
            .popover(isPresented: $showingCapacityPopover, arrowEdge: .top) {
                RuleCapacityPopoverView(filterManager: filterManager)
            }

            StatCard(
                title: "Enabled Lists",
                value: "\(enabledListsCount)",
                icon: "list.bullet.rectangle"
            )
            #if os(iOS)
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }
        .padding(.horizontal)
    }

    private func foreignFilterGroupHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 6)
    }

    private func filterRowView(for filter: FilterList) -> some View {
        FilterRowView(
            filter: filter,
            isInlineUserList: isInlineUserList(filter),
            supportsCustomActions: supportsCustomActions(filter),
            onEdit: { editingCustomFilter = filter },
            onDelete: { filterManager.removeFilterList(filter) },
            onToggle: { _ in filterManager.toggleFilterListSelection(id: filter.id) },
            onShowRuleLimitWarning: { filterManager.showRuleLimitWarning(for: filter) }
        )
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if supportsCustomActions(filter) {
                Button(role: .destructive) {
                    filterManager.removeFilterList(filter)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    editingCustomFilter = filter
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                filterManager.toggleFilterListSelection(id: filter.id)
            } label: {
                Label(
                    filter.isSelected ? "Disable" : "Enable",
                    systemImage: filter.isSelected ? "circle.slash" : "checkmark.circle"
                )
            }
            .tint(filter.isSelected ? .gray : .green)
        }
        #endif
    }

}

struct FilterRowView: View {
    let filter: FilterList
    let isInlineUserList: Bool
    let supportsCustomActions: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onToggle: (Bool) -> Void
    var onShowRuleLimitWarning: () -> Void

    @ViewBuilder
    private var contextMenuItems: some View {
        if supportsCustomActions {
            Button {
                onEdit()
            } label: {
                Label(isInlineUserList ? "Edit Rules" : "Edit Filter List", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Added List", systemImage: "trash")
            }
        }

        Button {
            #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(filter.url.absoluteString, forType: .string)
            #else
                UIPasteboard.general.string = filter.url.absoluteString
            #endif
        } label: {
            Label("Copy URL", systemImage: "doc.on.doc")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let flags = filter.flagEmojis {
                        Text(flags)
                    }
                    Text(filter.localizedDisplayName)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)

                if let rawCount = filter.rawSourceRuleCount,
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

                if let limitReason = filter.limitExceededReason {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text(limitReason)
                            .font(.caption2)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.orange)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
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
            Spacer()
            Toggle(
                "",
                isOn: Binding(
                    get: { filter.isSelected },
                    set: { newValue in
                        // Defer state change to next run loop to avoid layout invalidation during scroll
                        DispatchQueue.main.async {
                            if newValue && filter.limitExceededReason != nil {
                                onShowRuleLimitWarning()
                            }
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
    }
}

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
            .alert("No Updates Found", isPresented: $filterManager.showingNoUpdatesAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("No updates available.")
            }
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
                Task {
                    await ConcurrentLogManager.shared.info(
                        .startup, LocalizedStrings.text("wBlock application appeared"), metadata: [:])
                }
                filterManager.setUserScriptManager(userScriptManager)
                #if canImport(AppIntents) && !os(visionOS)
                applyShortcutFilterUpdateIfNeeded()
                #endif
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
            #if canImport(AppIntents) && !os(visionOS)
                .onReceive(
                    NotificationCenter.default.publisher(for: .shortcutFilterUpdateRequested)
                ) { _ in
                    applyShortcutFilterUpdateIfNeeded()
                }
            #endif
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
                .fullScreenCover(isPresented: $showOnboardingSheet) {
                    OnboardingView(filterManager: filterManager)
                }
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

    #if canImport(AppIntents) && !os(visionOS)
    private func applyShortcutFilterUpdateIfNeeded() {
        Task { @MainActor in
            await filterManager.waitUntilReady()
            guard ShortcutFilterUpdateRequest.shared.consumePendingRequest() else { return }
            applyFilterChangesFromExternalTrigger()
        }
    }
    #endif
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
        [.custom] + allCases.filter { $0 != .all && $0 != .custom }
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
    @State private var userListTitle: String = ""
    @State private var userListDescription: String = ""
    @State private var selectedCategory: FilterListCategory = .custom

    private enum AddMode: String, CaseIterable, Identifiable {
        case url = "URL"
        case paste = "Paste"
        case file = "File"

        var id: String { rawValue }
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
		    CompatibleNavigationStack {
		        addForm
		            .navigationTitle("Add Filter List")
		            #if os(iOS)
		            .navigationBarTitleDisplayMode(.inline)
		            #endif
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
		    #if os(iOS)
		    .largeSheetPresentationCompat()
		    #else
		    .frame(minWidth: 560, minHeight: addMode == .paste ? 620 : 520)
		    .onAppear {
		        urlFieldIsFocused = addMode == .url
		    }
		    .onChangeCompat(of: addMode) { _, newValue in
		        urlFieldIsFocused = newValue == .url
		    }
		    #endif
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType.plainText, UTType.text],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { @MainActor in
                    isSaving = true
                    defer { isSaving = false }

                    let title = userListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    let description = userListDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    url.withSecurityScopedAccess { accessibleURL in
						filterManager.addUserListFromFile(
							accessibleURL,
							nameOverride: title,
							description: description.isEmpty ? nil : description,
							category: selectedCategory
						)
                    }
                    if !filterManager.hasError {
                        dismiss()
                    } else {
                        importErrorMessage = filterManager.statusDescription
                    }
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
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

    private var addForm: some View {
        Form {
            Section {
                Picker("Add Mode", selection: $addMode) {
                    ForEach(AddMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .animation(.easeInOut(duration: 0.15), value: addMode)
            }

            modeContent
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch addMode {
        case .url:
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("URLs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    urlInputEditor
                }

                if newURLs.count <= 1 {
                    TextField("Title (optional)", text: $customName)
                        .autocorrectionDisabled()
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
        case .paste:
            Section {
                TextField("Title", text: $userListTitle)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.words)
                    #endif
                TextField("Description", text: $userListDescription)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                    #endif
                userListCategoryPicker(selection: $selectedCategory)
            }

            Section("Rules") {
                SyntaxHighlightingTextView(text: $pastedRules)
                    .frame(minHeight: 220)
            }
        case .file:
            Section {
                TextField("Title", text: $userListTitle)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.words)
                    #endif
                TextField("Description", text: $userListDescription)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                    #endif
                userListCategoryPicker(selection: $selectedCategory)
            }
        }
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
                Text("Paste one or more filter URLs, one per line.")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
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
            return !userListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            showingFileImporter = true
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
            return "Add URL"
        case .paste: return "Add Rules"
        case .file: return "Choose File"
        }
    }

    // MARK: - Helpers

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
        let candidate = trimmedCustomName
        guard newURLs.count <= 1, !candidate.isEmpty else { return false }
        return filterManager.filterLists.contains(where: {
            $0.name.caseInsensitiveCompare(candidate) == .orderedSame
        })
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
            CompatibleNavigationStack {
                Form {
                    Section {
                        TextField("Name", text: $name)
                            .focused($nameFieldIsFocused)
                            #if os(iOS)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                            #endif
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
                            .lineLimit(2)
                            .textSelection(.enabled)
                    } footer: {
                        if isDuplicate {
                            Text("That name is already used by another filter list.")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .navigationTitle("Edit Filter List")
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
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

    init(filterManager: AppFilterManager, filter: FilterList) {
        self.filterManager = filterManager
        self.filter = filter
        self._title = State(initialValue: filter.name)
        self._description = State(initialValue: filter.description == "User list." ? "" : filter.description)
        self._selectedCategory = State(initialValue: filter.category)
    }

    var body: some View {
        CompatibleNavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .focused($titleFieldIsFocused)
                        #if os(iOS)
                            .textInputAutocapitalization(.words)
                        #endif
                        .autocorrectionDisabled()

                    TextField("Description", text: $description)
                        #if os(iOS)
                            .textInputAutocapitalization(.sentences)
                        #endif
                        .autocorrectionDisabled()

                    userListCategoryPicker(selection: $selectedCategory)

                    Text(filter.url.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                } footer: {
                    if isDuplicateTitle {
                        Text("That title is already used by another filter list.")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Rules") {
                    SyntaxHighlightingTextView(text: $rules)
                        .frame(minHeight: 260)
                }
            }
            .navigationTitle("Edit User List")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isLoadingContent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
                #if os(iOS)
                ToolbarItem(placement: .principal) {
                    if isLoadingContent {
                        ProgressView()
                    }
                }
                #endif
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
        #if os(iOS)
        .largeSheetPresentationCompat()
        #endif
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

    private func loadContent() {
        isLoadingContent = true
        let filterID = filter.id
        let filterName = filter.name
        Task {
            let loadedRules = await Task.detached { () -> String? in
                guard let containerURL = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value
                ) else {
                    return nil
                }

                let idBasedURL = containerURL.appendingPathComponent("custom-\(filterID.uuidString).txt")
                if let loaded = try? String(contentsOf: idBasedURL, encoding: .utf8) {
                    return loaded
                }

                let legacyURL = containerURL.appendingPathComponent("\(filterName).txt")
                return try? String(contentsOf: legacyURL, encoding: .utf8)
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
        targets.count * 150_000
    }

    private var overallFraction: Double {
        totalCapacity > 0 ? min(Double(totalUsed) / Double(totalCapacity), 1.0) : 0.0
    }

    private func categorySubtitle(for slot: Int) -> String {
        switch slot {
        case 1: return String(localized: "Ads & Trackers")
        case 2: return String(localized: "Privacy & Anti-Tracking")
        case 3: return String(localized: "Security & Annoyances")
        case 4: return String(localized: "Regional & Language")
        case 5: return String(localized: "Custom & User Rules")
        default: return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Safari Rule Capacity", systemImage: "shield.lefthalf.filled")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
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
                        let slotFraction = min(Double(count) / 150_000.0, 1.0)
                        let subtitle = categorySubtitle(for: target.slot)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(target.displayName)
                                        .font(.subheadline.weight(.medium))
                                    if !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(count.formatted()) / 150,000")
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
        }
        .padding(16)
        #if os(macOS)
        .frame(width: 340)
        #else
        .frame(maxWidth: 380, maxHeight: .infinity, alignment: .top)
        #endif
    }
}
