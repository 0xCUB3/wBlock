//
//  ContentView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import Combine
import SafariServices
import SwiftUI
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
    @State private var showOnlyEnabledLists = false
    @Environment(\.scenePhase) var scenePhase

    private var hasCompletedOnboarding: Bool {
        dataManager.hasCompletedOnboarding
    }

    private var enabledListsCount: Int {
        filterManager.filterLists.filter { $0.isSelected }.count
    }

    private var sourceRulesCount: Int {
        filterManager.filterLists
            .filter { $0.isSelected }
            .compactMap { $0.sourceRuleCount }
            .reduce(0, +)
    }

    private var displayedRuleCount: Int {
        if filterManager.lastRuleCount > 0 {
            return filterManager.lastRuleCount
        } else {
            return sourceRulesCount
        }
    }

    private var displayableCategories: [FilterListCategory] {
        FilterListCategory.allCases.filter { $0 != .all && $0 != .custom }
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

        // Add custom lists at the end
        let customFilters = allFilters.filter {
            $0.category == .custom && (!showOnlyEnabledLists || $0.isSelected)
        }
        if !customFilters.isEmpty {
            result.append((category: .custom, filters: customFilters))
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
                minWidth: 520, idealWidth: 600, maxWidth: .infinity,
                minHeight: 500, idealHeight: 650, maxHeight: .infinity
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
            StatCard(
                title: "Applied Rules",
                value: displayedRuleCount.formatted(),
                icon: "shield.lefthalf.filled",
                pillColor: .clear,
                valueColor: .primary
            )
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

                if filterManager.isCategoryApproachingLimit(category) {
                    Button {
                        filterManager.showCategoryWarning(for: category)
                    } label: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

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

                    if filterManager.isCategoryApproachingLimit(.foreign) {
                        Button {
                            filterManager.showCategoryWarning(for: .foreign)
                        } label: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }

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
                    Text("(\(sourceCount.formatted()) rules)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if filter.sourceRuleCount == nil {
                    Text("(N/A rules)")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                                filterManager.showCategoryWarning(for: filter.category)
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
            .disabled(filter.limitExceededReason != nil && !filter.isSelected)
        }
        .padding(16)
        .id(filter.id)
        #if os(iOS)
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12))
        #endif
        .contentShape(.interaction, Rectangle())
        .contextMenu {
            if filter.category == .custom {
                Button(role: .destructive) {
                    filterManager.removeFilterList(filter)
                } label: {
                    Label("Delete Custom List", systemImage: "trash")
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
                "Category Rule Limit Warning",
                isPresented: $filterManager.showingCategoryWarningAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(filterManager.categoryWarningMessage)
            }
            .alert("Filters Auto-Disabled", isPresented: $filterManager.showingAutoDisabledAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                if filterManager.autoDisabledFilters.isEmpty {
                    Text(
                        "Some filters were automatically disabled because their category exceeded Safari's 150,000 rule limit."
                    )
                } else {
                    Text(
                        "The following filters were automatically disabled:\n\n\(filterManager.autoDisabledFilters.map { $0.name }.joined(separator: "\n"))\n\nTo re-enable these filters, disable other filters in the same category first."
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
                .fullScreenCover(
                    isPresented: Binding(
                        get: { !dataManager.isLoading && !dataManager.hasCompletedOnboarding },
                        set: { _ in }
                    )
                ) {
                    OnboardingView(filterManager: filterManager)
                }
            #elseif os(macOS)
                .sheet(
                    isPresented: Binding(
                        get: { !dataManager.isLoading && !dataManager.hasCompletedOnboarding },
                        set: { _ in }
                    )
                ) {
                    OnboardingView(filterManager: filterManager)
                }
            #endif
            // Critical Setup Checklist - appears after onboarding
            #if os(iOS)
                .fullScreenCover(
                    isPresented: Binding(
                        get: {
                            !dataManager.isLoading && dataManager.hasCompletedOnboarding
                                && !dataManager.hasCompletedCriticalSetup
                        },
                        set: { _ in }
                    )
                ) {
                    SetupChecklistView()
                }
            #elseif os(macOS)
                .sheet(
                    isPresented: Binding(
                        get: {
                            !dataManager.isLoading && dataManager.hasCompletedOnboarding
                                && !dataManager.hasCompletedCriticalSetup
                        },
                        set: { _ in }
                    )
                ) {
                    SetupChecklistView()
                }
            #endif
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
    @FocusState private var focusedField: Field?

    @State private var nameInput: String = ""
    @State private var urlInput: String = ""
    @State private var validationState: ValidationState = .idle
    @State private var showRequirements: Bool = false
    @State private var isSaving: Bool = false

    var body: some View {
        SheetContainer {
            SheetHeader(title: "Add Filter List", isLoading: isSaving) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    entryCard
                    requirementsCard
                }
                .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }

            SheetBottomToolbar {
                cancelButton
                Spacer()
                addButton
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            focusedField = .url
        }
        .onChange(of: urlInput) { _, newValue in
            validateInput(newValue)
        }
    }

    // MARK: - Content Sections

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Filter details")
                    .font(.headline)
                Text(
                    "Paste the URL to a supported filter list. You can optionally provide a custom name."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Filter name (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("e.g. My Essential Filters", text: $nameInput)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                            .textInputAutocapitalization(.words)
                        #endif
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .name)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Filter URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("https://example.com/filter.txt", text: $urlInput)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        #endif
                        .focused($focusedField, equals: .url)

                    HStack(spacing: 12) {
                        Button {
                            pasteFromClipboard()
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                urlInput = ""
                            }
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(urlInput.isEmpty)

                        Spacer()

                        validationBadge
                    }
                }
            }

            validationMessage
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var requirementsCard: some View {
        DisclosureGroup(isExpanded: $showRequirements.animation(.easeInOut(duration: 0.2))) {
            VStack(alignment: .leading, spacing: 8) {
                requirementRow(icon: "link", description: "Starts with https://")
                requirementRow(
                    icon: "doc.text", description: "Points to a filter file (.txt, .list, .json)")
                requirementRow(
                    icon: "checkmark.shield", description: "Hosted by a trusted provider")
                requirementRow(
                    icon: "arrow.triangle.2.circlepath",
                    description: "Accessible without authentication")
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("URL requirements")
                        .font(.headline)
                    Text("Tap to review filter list guidelines.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var validationBadge: some View {
        Group {
            switch validationState {
            case .idle:
                EmptyView()
            case .invalid:
                Label("Invalid", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .duplicate:
                Label("Duplicate", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .valid:
                Label("Ready", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: validationState)
    }

    private var validationMessage: some View {
        Group {
            switch validationState {
            case .idle:
                Text("We’ll download and enable the filter automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("Looks good! Tap Add Filter to continue.")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: validationState)
    }

    private func requirementRow(icon: String, description: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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
                Text(isSaving ? "Adding…" : "Add Filter")
                    .fontWeight(.semibold)
            }
        }
        .primaryActionButtonStyle()
        .disabled(!canSubmit)
        .keyboardShortcut(.defaultAction)
    }

    private var canSubmit: Bool {
        if case .valid = validationState, !isSaving {
            return true
        }
        return false
    }

    private func submit() {
        guard case .valid(let url) = validationState else { return }

        isSaving = true

        Task { @MainActor in
            let trimmedName = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = trimmedName.isEmpty ? defaultName(for: url) : trimmedName
            filterManager.addFilterList(name: finalName, urlString: url.absoluteString)
            isSaving = false
            dismiss()
        }
    }

    // MARK: - Helpers

    private func validateInput(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            validationState = .idle
            return
        }

        guard let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            let host = components.host,
            !host.isEmpty,
            let url = components.url
        else {
            validationState = .invalid
            return
        }

        if filterManager.filterLists.contains(where: {
            $0.url.absoluteString.lowercased() == url.absoluteString.lowercased()
        }) {
            validationState = .duplicate
            return
        }

        validationState = .valid(url)
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

    private func pasteFromClipboard() {
        #if os(iOS)
            if let string = UIPasteboard.general.string {
                urlInput = string
            }
        #elseif os(macOS)
            if let string = NSPasteboard.general.string(forType: .string) {
                urlInput = string
            }
        #endif
    }

    private enum ValidationState: Equatable {
        case idle
        case invalid
        case duplicate
        case valid(URL)
    }

    private enum Field: Hashable {
        case name
        case url
    }
}
