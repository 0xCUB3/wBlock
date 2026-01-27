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
        var result: [(category: FilterListCategory, filters: [FilterList])] = []

        for category in displayableCategories {
            let filters = allFilters.filter {
                $0.category == category && (!showOnlyEnabledLists || $0.isSelected)
            }
            if !filters.isEmpty {
                result.append((category: category, filters: filters))
            }
        }

        return result
    }

    var body: some View {
        #if os(iOS)
            if #available(iOS 18.0, *) {
                TabView {
                    Tab("Filters", systemImage: "list.bullet.rectangle") {
                        filtersView
                    }
                    Tab("Userscripts", systemImage: "doc.text.fill") {
                        userscriptsView
                    }
                    Tab("Settings", systemImage: "gear") {
                        settingsView
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
                    EditCustomFilterNameView(filterManager: filterManager, filter: filter)
                }
            } else {
                // iOS 17 fallback
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
                    EditCustomFilterNameView(filterManager: filterManager, filter: filter)
                }
            }
        #elseif os(macOS)
            // Use same liquid glass bottom tab bar as iOS
            TabView {
                filtersView
                    .tabItem {
                        Label("Filters", systemImage: "list.bullet.rectangle")
                    }
                userscriptsView
                    .tabItem {
                        Label("Userscripts", systemImage: "doc.text.fill")
                    }
                SettingsView(filterManager: filterManager)
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
                EditCustomFilterNameView(filterManager: filterManager, filter: filter)
            }
        #endif
    }

    private var filtersView: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statsCardsView

                    VStack(spacing: 16) {
                        ForEach(categorizedFilters, id: \.category) { item in
                            if item.category == .foreign {
                                foreignFiltersDisclosureView(filters: item.filters)
                            } else {
                                filterSectionView(category: item.category, filters: item.filters)
                            }
                        }
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 20)
                }
                .padding(.vertical)
            }
            #if os(iOS)
                .padding(.horizontal, 16)
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
                        .disabled(filterManager.isLoading || enabledListsCount == 0)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        HStack {
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
                }
            #endif
        }
        #if os(macOS)
            .frame(
                minWidth: 480, idealWidth: 540, maxWidth: .infinity,
                minHeight: 550, idealHeight: 720, maxHeight: .infinity
            )
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        Task {
                            await filterManager.checkAndEnableFilters(forceReload: true)
                        }
                    } label: {
                        Label("Apply Changes", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(filterManager.isLoading || enabledListsCount == 0)

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
                            .disabled(filterManager.isLoading || enabledListsCount == 0)
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
            StatCard(
                title: "Enabled Lists",
                value: "\(enabledListsCount)",
                icon: "list.bullet.rectangle",
                pillColor: .clear,
                valueColor: .primary
            )
            #if os(iOS)
                Button {
                    filterManager.showRuleLimitWarning()
                } label: {
                    StatCard(
                        title: "Rules",
                        value: hasAppliedFilters
                            ? appliedSafariRulesCount.formatted()
                            : (sourceRulesCount > 0 ? "~\(sourceRulesCount.formatted())" : "0"),
                        icon: "shield.lefthalf.filled",
                        pillColor: .clear,
                        valueColor: hasAppliedFilters ? .primary : .secondary
                    )
                    .overlay(alignment: .topTrailing) {
                        if shouldShowRuleLimitIndicator {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.trailing, 10)
                                .padding(.top, 8)
                        }
                    }
                }
                .buttonStyle(.plain)
            #else
                Button {
                    filterManager.showRuleLimitWarning()
                } label: {
                    StatCard(
                        title: hasAppliedFilters ? "Safari Rules" : "Source Rules",
                        value: hasAppliedFilters
                            ? appliedSafariRulesCount.formatted()
                            : (sourceRulesCount > 0 ? "~\(sourceRulesCount.formatted())" : "0"),
                        icon: "shield.lefthalf.filled",
                        pillColor: .clear,
                        valueColor: hasAppliedFilters ? .primary : .secondary
                    )
                    .overlay(alignment: .topTrailing) {
                        if shouldShowRuleLimitIndicator {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.trailing, 10)
                                .padding(.top, 8)
                        }
                    }
                }
                .buttonStyle(.plain)
            #endif
        }
        .padding(.horizontal)
    }

    private func filterSectionView(category: FilterListCategory, filters: [FilterList]) -> some View
    {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.rawValue)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(filters) { filter in
                    filterRowView(filter: filter)

                    if filter.id != filters.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func foreignFiltersDisclosureView(filters: [FilterList]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Manual expand/collapse button instead of DisclosureGroup (avoids LazyVStack bug)
            Button {
                Task {
                    await dataManager.setIsForeignFiltersExpanded(
                        !dataManager.isForeignFiltersExpanded)
                }
            } label: {
                HStack {
                    Text(FilterListCategory.foreign.rawValue)
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
                        filterRowView(filter: filter)

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

    private func filterRowView(filter: FilterList) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(filter.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                if let sourceCount = filter.sourceRuleCount, sourceCount > 0 {
                    Text("(\(sourceCount.formatted()) source rules)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if filter.sourceRuleCount == nil {
                    // Filter not yet downloaded or count not calculated
                    Text("(pending)")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.6))
                }

                if !filter.description.isEmpty {
                    Text(filter.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                }

                if let limitReason = filter.limitExceededReason {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text(limitReason)
                            .font(.caption2)
                            .lineLimit(nil)
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
                                filterManager.showRuleLimitWarning(for: filter)
                                filterManager.toggleFilterListSelection(id: filter.id)
                            } else {
                                filterManager.toggleFilterListSelection(id: filter.id)
                            }
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .frame(alignment: .center)
        }
        .padding(16)
        .id(filter.id)
        #if os(iOS)
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12))
        #endif
        .contentShape(.interaction, Rectangle())
        .contextMenu {
            if filter.isCustom {
                Button {
                    editingCustomFilter = filter
                } label: {
                    Label("Edit Name", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    filterManager.removeFilterList(filter)
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
    @State private var showSetupChecklistSheet = false
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
                    // Onboarding was just completed, hide onboarding and maybe show setup
                    showOnboardingSheet = false
                    if !dataManager.hasCompletedCriticalSetup {
                        showSetupChecklistSheet = true
                    }
                } else if !newValue && oldValue {
                    // Onboarding was reset (e.g., from Settings), show onboarding again
                    showSetupChecklistSheet = false
                    showOnboardingSheet = true
                }
            }
            // Only react to hasCompletedCriticalSetup becoming true
            .onChange(of: dataManager.hasCompletedCriticalSetup) { oldValue, newValue in
                if newValue && !oldValue {
                    showSetupChecklistSheet = false
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
                    print("Received applyWBlockChangesNotification in ContentView.")
                    print("Triggering applyChanges from notification observer.")
                    filterManager.showingApplyProgressSheet = true
                    Task {
                        await filterManager.checkAndEnableFilters(forceReload: true)
                    }
                }
                .fullScreenCover(isPresented: $showOnboardingSheet) {
                    OnboardingView(filterManager: filterManager)
                }
                .fullScreenCover(isPresented: $showSetupChecklistSheet) {
                    SetupChecklistView()
                }
            #elseif os(macOS)
                .sheet(isPresented: $showOnboardingSheet) {
                    OnboardingView(filterManager: filterManager)
                }
                .sheet(isPresented: $showSetupChecklistSheet) {
                    SetupChecklistView()
                }
            #endif
    }

    /// Determines which sheet (if any) should be shown on initial app load.
    /// Called only once after initial data load completes.
    private func updateSheetPresentation() {
        // Priority 1: Show onboarding if not completed
        if !dataManager.hasCompletedOnboarding {
            showOnboardingSheet = true
            return
        }

        // Priority 2: Show setup checklist if onboarding is done but critical setup isn't
        if !dataManager.hasCompletedCriticalSetup {
            showSetupChecklistSheet = true
        }
    }

    #if os(iOS)
        private func scheduleNotification(delay: TimeInterval = 1.0) {
            let content = UNMutableNotificationContent()
            content.title = "Psst! You forgot something!"
            content.body = "You have unapplied filter changes in wBlock. Tap to apply them now!"
            content.sound = .default
            content.userInfo = ["action_type": "apply_wblock_changes"]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling notification: \(error.localizedDescription)")
                } else {
                    print("Notification scheduled successfully.")
                }
            }
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

    private enum AddMode: String, CaseIterable, Identifiable {
        case url = "URL"
        case paste = "Paste"
        case file = "File"

        var id: String { rawValue }
    }

    @State private var addMode: AddMode = .url

    private var validationState: ValidationState {
        validationState(for: urlInput)
    }

    var body: some View {
        SheetContainer {
            SheetHeader(title: "Add Filter List", isLoading: isSaving) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    entryCard
                }
                .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
            #endif

            SheetBottomToolbar {
                Spacer()
                addButton
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            urlFieldIsFocused = addMode == .url
        }
        .onChange(of: addMode) { _, newValue in
            urlFieldIsFocused = newValue == .url
        }
        #if os(iOS)
            .presentationDetents(addMode == .paste ? [.large] : [.height(340)])
            .presentationDragIndicator(.visible)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }

                    Spacer()

                    Button("Clear") {
                        urlInput = ""
                    }
                    .disabled(urlInput.isEmpty)

                    Button("Done") {
                        urlFieldIsFocused = false
                    }
                }
            }
        #endif
    }

    // MARK: - Content Sections

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Add Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            Picker("", selection: $addMode) {
                ForEach(AddMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            #if os(macOS)
                .controlSize(.small)
            #endif
            .animation(.easeInOut(duration: 0.15), value: addMode)
        }

            switch addMode {
            case .url:
                VStack(alignment: .leading, spacing: 6) {
                    Text("URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("https://example.com/filter.txt", text: $urlInput)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
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
                }
            case .file:
                Button {
                    showingFileImporter = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc")
                        Text("Choose Filter File…")
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
                .disabled(isSaving)
            case .paste:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rules")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $pastedRules)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 220)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.quaternary, lineWidth: 1)
                        )

                    HStack(spacing: 10) {
                        #if os(iOS)
                            Button {
                                if let string = UIPasteboard.general.string {
                                    pastedRules = string
                                }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                            .secondaryActionButtonStyle()
                            .disabled(isSaving)
                        #endif

                        Spacer()

                        Button("Clear") {
                            pastedRules = ""
                        }
                        .secondaryActionButtonStyle()
                        .disabled(isSaving || pastedRules.isEmpty)
                    }
                }
            }

            DisclosureGroup(isExpanded: $isNameSectionExpanded) {
                TextField(namePlaceholder, text: $customName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.words)
                    #endif
            } label: {
                HStack(spacing: 10) {
                    Text("Name (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !trimmedCustomName.isEmpty && !isNameSectionExpanded {
                        Text(trimmedCustomName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            validationMessage
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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

                    filterManager.addUserListFromFile(url, nameOverride: trimmedCustomName.isEmpty ? nil : trimmedCustomName)
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
        .alert("Couldn’t Add List", isPresented: Binding(get: { importErrorMessage != nil }, set: { _ in importErrorMessage = nil })) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private var validationMessage: some View {
        Group {
            if isCustomNameDuplicate {
                Text("That name is already used by another filter list.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            switch validationState {
            case .idle:
                EmptyView()
            case .invalid:
                Text(
                    "Provide a valid https:// link to a filter file ending in .txt, .list, or .json."
                )
                .font(.caption)
                .foregroundStyle(.orange)
            case .duplicate:
                Text("A filter list with this URL already exists in wBlock.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .valid:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: validationState)
    }

    private var cancelButton: some View {
        Button("Cancel") {
            dismiss()
        }
        .secondaryActionButtonStyle()
        .disabled(isSaving)
        .keyboardShortcut(.cancelAction)
    }

    private var addButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.9)
                }
                Text(isSaving ? "Adding…" : addButtonTitle)
                    .fontWeight(.semibold)
            }
        }
        .primaryActionButtonStyle()
        .disabled(!canSubmit)
        .keyboardShortcut(.defaultAction)
    }

    private var canSubmit: Bool {
        if isSaving || isCustomNameDuplicate { return false }
        switch addMode {
        case .url:
            if case .valid = validationState { return true }
            return false
        case .paste:
            return !pastedRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file:
            return false
        }
    }

    private func submit() {
        switch addMode {
        case .url:
            guard case .valid(let url) = validationState else { return }
            isSaving = true
            Task { @MainActor in
                let finalName = trimmedCustomName.isEmpty ? defaultName(for: url) : trimmedCustomName
                filterManager.addFilterList(
                    name: finalName,
                    urlString: url.absoluteString,
                    category: .custom
                )
                isSaving = false
                dismiss()
            }
        case .paste:
            isSaving = true
            Task { @MainActor in
                let finalName = trimmedCustomName.isEmpty ? "User List" : trimmedCustomName
                let finalRules = pastedRules.trimmingCharacters(in: .whitespacesAndNewlines)
                filterManager.addUserList(name: finalName, content: finalRules, isSelected: true)
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

    private var namePlaceholder: String {
        if case .valid(let url) = validationState {
            return defaultName(for: url)
        }
        return "Custom name"
    }

    private enum ValidationState: Equatable {
        case idle
        case invalid
        case duplicate
        case valid(URL)
    }

    #if os(iOS)
        private func pasteFromClipboard() {
            if let string = UIPasteboard.general.string {
                urlInput = string
            }
        }
    #endif
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
            #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
            #endif

            SheetBottomToolbar {
                Spacer()
                saveButton
            }
        }
        .onAppear {
            nameFieldIsFocused = true
        }
        #if os(iOS)
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        #endif
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
