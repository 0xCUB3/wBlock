//
//  ContentView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import Combine
import SafariServices
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
                    filter.name.localizedCaseInsensitiveContains(query)
                        || filter.description.localizedCaseInsensitiveContains(query)
                        || filter.url.absoluteString.localizedCaseInsensitiveContains(query)
                }
            if !searched.isEmpty {
                result.append((category: category, filters: searched))
            }
        }

        return result
    }

    var body: some View {
        #if os(iOS)
            TabView {
                filtersView
                    .tabItem {
                        Label("Filters", systemImage: "list.bullet.rectangle")
                    }
                userscriptsView
                    .tabItem {
                        Label("Userscripts", systemImage: "doc.text.fill")
                    }
                settingsView
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
                    EditCustomFilterNameView(filterManager: filterManager, filter: filter)
                }
            }
        #elseif os(macOS)
            TabView {
                filtersView
                    .tabItem {
                        Label("Filters", systemImage: "list.bullet.rectangle")
                    }
                userscriptsView
                    .tabItem {
                        Label("Userscripts", systemImage: "doc.text.fill")
                    }
                settingsView
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
                    EditCustomFilterNameView(filterManager: filterManager, filter: filter)
                }
            }
        #endif
    }

    private func isInlineUserList(_ filter: FilterList) -> Bool {
        filter.url.scheme?.lowercased() == "wblock"
            && filter.url.host?.lowercased() == "userlist"
    }

    private func supportsCustomActions(_ filter: FilterList) -> Bool {
        filter.isCustom || filterManager.customFilterLists.contains(where: { $0.id == filter.id })
    }

    private var filtersView: some View {
        NavigationStack {
            nativeFiltersListView
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Task {
                                await filterManager.checkAndEnableFilters(forceReload: true)
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .disabled(filterManager.isLoading)
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
            .searchable(
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
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    ToolbarSearchField(
                        text: $filterSearchText,
                        isExpanded: $showFilterSearch,
                        prompt: "Search filters"
                    )

                    if !showFilterSearch {
                        Button {
                            Task {
                                await filterManager.checkAndEnableFilters(forceReload: true)
                            }
                        } label: {
                            Label("Apply Changes", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(filterManager.isLoading)

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
            }
        #endif
    }

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
                        if dataManager.isForeignFiltersExpanded {
                            ForEach(item.filters) { filter in
                                filterRowView(for: filter)
                            }
                        }
                    } header: {
                        Button {
                            Task {
                                await dataManager.setIsForeignFiltersExpanded(
                                    !dataManager.isForeignFiltersExpanded
                                )
                            }
                        } label: {
                            HStack {
                                Text(item.category.localizedName)
                                Spacer()
                                Image(
                                    systemName: dataManager.isForeignFiltersExpanded
                                        ? "chevron.down"
                                        : "chevron.right"
                                )
                                .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .textCase(nil)
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
        #else
        ScrollView {
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
        #endif
    }

    private var userscriptsView: some View {
        NavigationStack {
            UserScriptManagerView(userScriptManager: userScriptManager)
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                Task {
                                    await filterManager.checkAndEnableFilters(forceReload: true)
                                }
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            .disabled(filterManager.isLoading)
                        }
                    }
                #endif
        }
    }

    private var settingsView: some View {
        SettingsView(filterManager: filterManager)
    }

    private var statsCardsView: some View {
        HStack(spacing: 12) {
            Button {
                filterManager.showRuleLimitWarning()
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
                    pillColor: .clear,
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

            StatCard(
                title: "Enabled Lists",
                value: "\(enabledListsCount)",
                icon: "list.bullet.rectangle",
                pillColor: .clear,
                valueColor: .primary
            )
            #if os(iOS)
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }
        .padding(.horizontal)
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
    }

    #if os(macOS)
    private func macOSFilterSectionView(category: FilterListCategory, filters: [FilterList]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.localizedName)
                    .font(.headline)
                    .foregroundColor(.primary)
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
            Button {
                Task {
                    await dataManager.setIsForeignFiltersExpanded(
                        !dataManager.isForeignFiltersExpanded)
                }
            } label: {
                HStack {
                    Text(FilterListCategory.foreign.localizedName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(
                        systemName: dataManager.isForeignFiltersExpanded
                            ? "chevron.down" : "chevron.right"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            if dataManager.isForeignFiltersExpanded {
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
    }
    #endif
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
                Label(isInlineUserList ? "Edit Rules" : "Edit Name", systemImage: "pencil")
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
                    Text(filter.name)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)

                if let rawCount = filter.rawSourceRuleCount,
                   let expandedCount = filter.sourceRuleCount,
                   rawCount != expandedCount {
                    // Both counts available and different — show expansion
                    Text("(\(rawCount.formatted()) source \u{2192} \(expandedCount.formatted()) expanded rules)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let count = filter.sourceRuleCount, count > 0 {
                    // Single count (no expansion, counts match, or rawSourceRuleCount is nil after restart)
                    Text("(\(count.formatted()) rules)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if filter.sourceRuleCount == nil {
                    // Filter not yet downloaded or count not calculated
                    Text("(pending)")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !filter.description.isEmpty {
                    Text(filter.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                    .foregroundColor(.orange)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }

                HStack(spacing: 4) {
                    if !filter.version.isEmpty {
                        Text("Version \(filter.version)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }

                    if let lastUpdatedFormatted = filter.lastUpdatedFormatted {
                        if !filter.version.isEmpty {
                            Text("·")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        Text(lastUpdatedFormatted)
                            .font(.caption2)
                            .foregroundColor(.gray)
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
        #if os(macOS)
        .padding(16)
        #endif
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
            .sheet(isPresented: $filterManager.showingUpdatePopup) {
                UpdatePopupView(
                    filterManager: filterManager, userScriptManager: userScriptManager,
                    isPresented: $filterManager.showingUpdatePopup)
            }
            .sheet(isPresented: $filterManager.showingApplyProgressSheet) {
                ApplyChangesProgressView(
                    viewModel: filterManager.applyProgressViewModel,
                    isPresented: $filterManager.showingApplyProgressSheet
                )
            }
            .alert("No Updates Found", isPresented: $filterManager.showingNoUpdatesAlert) {
                Button("OK", role: .cancel) {}
            }
            .alert(
                "Rule Limit Warning",
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
                    Text(
                        "Some filters were automatically disabled because Safari's rule limits were exceeded."
                    )
                } else {
                    Text(
                        "The following filters were automatically disabled:\n\n\(filterManager.autoDisabledFilters.map { $0.name }.joined(separator: "\n"))\n\nTo re-enable these filters, disable other large filters and apply changes again."
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
                    && !filterManager.showingUpdatePopup
                    && !filterManager.suppressBlockingOverlay
                {
                    ZStack {
                        Color.black.opacity(0.1).ignoresSafeArea()
                        VStack {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text(filterManager.statusDescription)
                                .padding(.top, 10)
                                .foregroundColor(.secondary)
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
                        .startup, "wBlock application appeared", metadata: [:])
                }
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
            .onChange(of: dataManager.hasCompletedOnboarding) { oldValue, newValue in
                if newValue && !oldValue {
                    showOnboardingSheet = false
                } else if !newValue && oldValue {
                    // Onboarding was reset (e.g., from Settings), show onboarding again
                    showOnboardingSheet = true
                }
            }
            #if os(iOS)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .background && filterManager.hasUnappliedChanges {
                        scheduleNotification(delay: 1)
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .applyWBlockChangesNotification)
                ) { _ in
                    filterManager.showingApplyProgressSheet = true
                    Task {
                        await filterManager.checkAndEnableFilters(forceReload: true)
                    }
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

    private var addableCategories: [FilterListCategory] {
        let remainingCategories = FilterListCategory.allCases.filter { category in
            category != .all && category != .custom
        }
        return [.custom] + remainingCategories
    }

    private var validationState: ValidationState {
        validationState(for: urlInput)
    }

		var body: some View {
		    Group {
		        #if os(iOS)
		            NavigationStack {
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
		            .presentationDetents([.large])
		            .presentationDragIndicator(.visible)
	        #elseif os(macOS)
	            macosBody
	        #endif
	    }
        #if os(macOS)
	    .onAppear {
	        urlFieldIsFocused = addMode == .url
	    }
        .onChange(of: addMode) { _, newValue in
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
                    var didAccess = false
                    #if os(iOS)
                        didAccess = url.startAccessingSecurityScopedResource()
                    #endif
                    defer {
                        #if os(iOS)
                            if didAccess { url.stopAccessingSecurityScopedResource() }
                        #endif
                    }

                    let title = userListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    let description = userListDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                    filterManager.addUserListFromFile(
                        url,
                        nameOverride: title,
                        description: description.isEmpty ? nil : description
                    )
                    isSaving = false
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
	            HStack(spacing: 10) {
	                Text("Add Mode")
	                    .font(.caption)
	                    .foregroundStyle(.secondary)

	                Picker("", selection: $addMode) {
	                    ForEach(AddMode.allCases) { mode in
	                        Text(LocalizedStringKey(mode.rawValue)).tag(mode)
	                    }
	                }
	                .pickerStyle(.segmented)
	                .labelsHidden()
	                .controlSize(.small)
	                .animation(.easeInOut(duration: 0.15), value: addMode)

	                Spacer(minLength: 0)
	            }
	            .padding(16)
	            .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
	        }

	        @ViewBuilder
	        private var macosModeContent: some View {
	            switch addMode {
	            case .url:
	                macosURLCard
	            case .paste:
	                macosPasteCard
	            case .file:
	                macosFileCard
	            }
	        }

	        private var macosURLCard: some View {
	            VStack(alignment: .leading, spacing: 12) {
	                VStack(alignment: .leading, spacing: 6) {
	                    Text("URL")
	                        .font(.caption)
	                        .foregroundStyle(.secondary)

	                    TextField("https://example.com/filter.txt", text: $urlInput)
	                        .textFieldStyle(.roundedBorder)
	                        .autocorrectionDisabled()
	                        .focused($urlFieldIsFocused)
	                        .onSubmit {
	                            if canSubmit {
	                                submit()
	                            } else {
	                                urlFieldIsFocused = false
	                            }
	                        }
	                }

	                VStack(alignment: .leading, spacing: 6) {
	                    Text("Title (optional)")
	                        .font(.caption)
	                        .foregroundStyle(.secondary)

	                    TextField("Title", text: $customName)
	                        .textFieldStyle(.roundedBorder)
	                        .autocorrectionDisabled()
	                }

	                VStack(alignment: .leading, spacing: 6) {
	                    Text("Category")
	                        .font(.caption)
	                        .foregroundStyle(.secondary)

	                    Picker("Category", selection: $selectedCategory) {
	                        ForEach(addableCategories) { category in
	                            Text(category.localizedName).tag(category)
	                        }
	                    }
	                    .pickerStyle(.menu)
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

	                    TextEditor(text: $pastedRules)
	                        .font(.system(.body, design: .monospaced))
	                        .frame(minHeight: 260)
	                        .scrollContentBackground(.hidden)
	                        .padding(10)
	                        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
	                        .overlay(
	                            RoundedRectangle(cornerRadius: 12, style: .continuous)
	                                .stroke(.quaternary, lineWidth: 1)
	                        )
	                }
	            }
	            .padding(16)
	            .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
	        }

	        private var macosFileCard: some View {
	            VStack(alignment: .leading, spacing: 12) {
	                userListMetaFields

	                Button {
	                    showingFileImporter = true
	                } label: {
	                    HStack(spacing: 10) {
	                        Image(systemName: "doc")
	                        Text("Choose File…")
	                        Spacer()
	                        Image(systemName: "chevron.right")
	                            .font(.caption2)
	                            .foregroundStyle(.secondary)
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
	                .disabled(isSaving || !canSubmit)
	            }
	            .padding(16)
	            .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
	        }
	    #endif

	    private var addTabs: some View {
	        TabView(selection: $addMode) {
	            urlTab
	                .tag(AddMode.url)
	                .tabItem { Label("URL", systemImage: "link") }

	            pasteTab
	                .tag(AddMode.paste)
	                .tabItem { Label("Paste", systemImage: "text.badge.plus") }

	            fileTab
	                .tag(AddMode.file)
	                .tabItem { Label("File", systemImage: "doc") }
	        }
	    }

		    private var urlTab: some View {
		        Form {
		            Section {
		                TextField(
		                    text: $urlInput,
		                    prompt: Text(verbatim: "https://example.com/filter.txt")
		                        .foregroundStyle(.secondary)
		                ) {
		                    Text("URL")
		                }
		                .accessibilityLabel("URL")
		                    #if os(iOS)
		                        .textInputAutocapitalization(.never)
		                        .keyboardType(.URL)
		                        .submitLabel(.done)
		                    #endif
	                    .focused($urlFieldIsFocused)
	                    .onSubmit {
	                        if canSubmit {
	                            submit()
	                        } else {
	                            urlFieldIsFocused = false
	                        }
	                    }

	                TextField("Title (optional)", text: $customName)
	                    #if os(iOS)
	                        .textInputAutocapitalization(.words)
	                    #endif

	                Picker("Category", selection: $selectedCategory) {
	                    ForEach(addableCategories) { category in
	                        Text(category.localizedName).tag(category)
	                    }
	                }
	                .pickerStyle(.menu)
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
	            }

		            Section("Rules") {
		                TextEditor(text: $pastedRules)
		                    .font(.system(.body, design: .monospaced))
		                    .frame(minHeight: 220)
		            }
		        }
		    }

		    private var fileTab: some View {
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
		            }
		        }
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
	                    Text("Enter a valid http(s) URL to a .txt, .list, or .json filter.")
	                        .foregroundStyle(.orange)
	                case .duplicate:
	                    Text("A filter list with this URL already exists in wBlock.")
	                        .foregroundStyle(.orange)
	                case .valid:
	                    EmptyView()
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
            guard case .valid(let url) = validationState else { return }
            isSaving = true
            Task { @MainActor in
                let userProvidedName = !trimmedCustomName.isEmpty
                let finalName = userProvidedName ? trimmedCustomName : defaultName(for: url)
                filterManager.addFilterList(
                    name: finalName,
                    urlString: url.absoluteString,
                    category: selectedCategory,
                    hasUserProvidedName: userProvidedName
                )
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
        case .url: return "Add URL"
        case .paste: return "Add Rules"
        case .file: return "Choose File"
        }
    }

    private var userListMetaFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("User List", text: $userListTitle)
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
        }
    }

    // MARK: - Helpers

    private func validationState(for rawValue: String) -> ValidationState {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .idle
        }

        guard let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            let host = components.host,
            !host.isEmpty,
            let url = components.url
        else {
            return .invalid
        }

        if filterManager.filterLists.contains(where: {
            $0.url.absoluteString.lowercased() == url.absoluteString.lowercased()
        }) {
            return .duplicate
        }

        return .valid(url)
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
        guard !candidate.isEmpty else { return false }
        return filterManager.filterLists.contains(where: {
            $0.name.caseInsensitiveCompare(candidate) == .orderedSame
        })
    }

    private enum ValidationState: Equatable {
        case idle
        case invalid
        case duplicate
        case valid(URL)
    }

}

struct EditCustomFilterNameView: View {
    @ObservedObject var filterManager: AppFilterManager
    let filter: FilterList

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFieldIsFocused: Bool

    @State private var name: String

    init(filterManager: AppFilterManager, filter: FilterList) {
        self.filterManager = filterManager
        self.filter = filter
        self._name = State(initialValue: filter.name)
    }

    var body: some View {
        Group {
            #if os(iOS)
                NavigationStack {
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
                    .navigationTitle("Edit Name")
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
                    SheetHeader(title: "Edit Name") {
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
        filterManager.updateCustomFilterListName(id: filter.id, newName: trimmedName)
        dismiss()
    }
}

struct EditUserListView: View {
    @ObservedObject var filterManager: AppFilterManager
    let filter: FilterList

    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFieldIsFocused: Bool

    @State private var title: String
    @State private var description: String
    @State private var rules: String = ""
    @State private var isLoadingContent: Bool = true
    @State private var errorMessage: String?

    init(filterManager: AppFilterManager, filter: FilterList) {
        self.filterManager = filterManager
        self.filter = filter
        self._title = State(initialValue: filter.name)
        self._description = State(initialValue: filter.description == "User list." ? "" : filter.description)
    }

    var body: some View {
        Group {
            #if os(iOS)
                NavigationStack {
                    Form {
                        Section {
                            TextField("Title", text: $title)
                                .focused($titleFieldIsFocused)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()

                            TextField("Description", text: $description)
                                .textInputAutocapitalization(.sentences)
                                .autocorrectionDisabled()
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
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
                                Text("Rules")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

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
        Task { @MainActor in
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: GroupIdentifier.shared.value
            ) else {
                isLoadingContent = false
                return
            }

            let idBasedURL = containerURL.appendingPathComponent("custom-\(filter.id.uuidString).txt")
            if let loaded = try? String(contentsOf: idBasedURL, encoding: .utf8) {
                rules = loaded
                isLoadingContent = false
                return
            }

            let legacyURL = containerURL.appendingPathComponent("\(filter.name).txt")
            if let loaded = try? String(contentsOf: legacyURL, encoding: .utf8) {
                rules = loaded
            }
            isLoadingContent = false
        }
    }

    private func save() {
        filterManager.updateUserList(
            id: filter.id,
            name: trimmedTitle,
            description: description,
            content: trimmedRules
        )
        if filterManager.hasError {
            errorMessage = filterManager.statusDescription
        } else {
            dismiss()
        }
    }
}
