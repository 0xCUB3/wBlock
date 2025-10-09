//
//  ContentView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI
import wBlockCoreService
import UserNotifications

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
        if (filterManager.lastRuleCount > 0) {
            return filterManager.lastRuleCount
        } else {
            return sourceRulesCount
        }
    }

    private var displayableCategories: [FilterListCategory] {
        FilterListCategory.allCases.filter { $0 != .all && $0 != .custom }
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
            .modifier(ContentModifiers(
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
            .modifier(ContentModifiers(
                filterManager: filterManager,
                userScriptManager: userScriptManager,
                dataManager: dataManager,
                showingAddFilterSheet: $showingAddFilterSheet,
                scenePhase: scenePhase
            ))
        }
        #elseif os(macOS)
        if #available(macOS 15.0, *) {
            TabView {
                Tab("Filters", systemImage: "list.bullet.rectangle") {
                    filtersView
                }
                Tab("Userscripts", systemImage: "doc.text.fill") {
                    UserScriptManagerView(userScriptManager: userScriptManager)
                }
                Tab("Whitelist", systemImage: "list.bullet.indent") {
                    WhitelistManagerView(filterManager: filterManager)
                }
                Tab("Settings", systemImage: "gear") {
                    SettingsView(filterManager: filterManager)
                }
            }
            .modifier(ContentModifiers(
                filterManager: filterManager,
                userScriptManager: userScriptManager,
                dataManager: dataManager,
                showingAddFilterSheet: $showingAddFilterSheet,
                scenePhase: scenePhase
            ))
        } else {
            // macOS 14 fallback
            TabView {
                filtersView
                    .tabItem {
                        Label("Filters", systemImage: "list.bullet.rectangle")
                    }
                UserScriptManagerView(userScriptManager: userScriptManager)
                    .tabItem {
                        Label("Userscripts", systemImage: "doc.text.fill")
                    }
                WhitelistManagerView(filterManager: filterManager)
                    .tabItem {
                        Label("Whitelist", systemImage: "list.bullet.indent")
                    }
                SettingsView(filterManager: filterManager)
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .modifier(ContentModifiers(
                filterManager: filterManager,
                userScriptManager: userScriptManager,
                dataManager: dataManager,
                showingAddFilterSheet: $showingAddFilterSheet,
                scenePhase: scenePhase
            ))
        }
        #endif
    }

    private var filtersView: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statsCardsView

                    LazyVStack(spacing: 16) {
                        ForEach(displayableCategories) { category in
                            let listsForCategory = self.listsForCategory(category)
                            if !listsForCategory.isEmpty {
                                filterSectionView(category: category, filters: listsForCategory)
                            }
                        }

                        let customLists = self.customLists
                        if !customLists.isEmpty {
                            filterSectionView(category: .custom, filters: customLists)
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
                            Task {
                                await filterManager.checkForUpdates()
                            }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .disabled(filterManager.isLoading)
                        Button {
                            showingAddFilterSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        Button {
                            showOnlyEnabledLists.toggle()
                        } label: {
                            Image(systemName: showOnlyEnabledLists ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, maxWidth: .infinity,
               minHeight: 500, idealHeight: 650, maxHeight: .infinity)
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
                    Label("Show Enabled Only", systemImage: showOnlyEnabledLists ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
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

    private func listsForCategory(_ category: FilterListCategory) -> [FilterList] {
        filterManager.filterLists.filter { $0.category == category && (!showOnlyEnabledLists || $0.isSelected) }
    }

    private var customLists: [FilterList] {
        filterManager.filterLists.filter { $0.category == .custom && (!showOnlyEnabledLists || $0.isSelected) }
    }

    private func filterSectionView(category: FilterListCategory, filters: [FilterList]) -> some View {
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
                ForEach(Array(filters.enumerated()), id: \.element.id) { index, filter in
                    filterRowView(filter: filter)

                    if index < filters.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func filterRowView(filter: FilterList) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(filter.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let sourceCount = filter.sourceRuleCount, sourceCount > 0 {
                    Text("(\(sourceCount.formatted()) rules)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if filter.sourceRuleCount == nil && filter.isSelected && !filterManager.doesFilterFileExist(filter) {
                    Text("(Counting...)")
                        .font(.caption)
                        .foregroundColor(.orange)
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
                        .fixedSize(horizontal: false, vertical: true)
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
            Toggle("", isOn: Binding(
                get: { filter.isSelected },
                set: { newValue in
                    filterManager.toggleFilterListSelection(id: filter.id)
                }
            ))
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
        .task(id: filter.id) {
            if filter.sourceRuleCount == nil && filterManager.doesFilterFileExist(filter) {
                await filterManager.updateVersionsAndCounts()
            }
        }
    }

    #if os(iOS)
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleNotification(delay: TimeInterval = 1.0) {
        let content = UNMutableNotificationContent()
        content.title = "Psst! You forgot something!"
        content.body = "You have unapplied filter changes in wBlock. Tap to apply them now!"
        content.sound = .default
        content.userInfo = ["action_type": "apply_wblock_changes"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

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

struct ContentModifiers: ViewModifier {
    @ObservedObject var filterManager: AppFilterManager
    @ObservedObject var userScriptManager: UserScriptManager
    let dataManager: ProtobufDataManager
    @Binding var showingAddFilterSheet: Bool
    let scenePhase: ScenePhase

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showingAddFilterSheet) {
                AddFilterListView(filterManager: filterManager)
            }
            .sheet(isPresented: $filterManager.showingUpdatePopup) {
                UpdatePopupView(filterManager: filterManager, userScriptManager: userScriptManager, isPresented: $filterManager.showingUpdatePopup)
            }
            .sheet(isPresented: $filterManager.showMissingItemsSheet) {
                MissingItemsView(filterManager: filterManager)
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
            .alert("Download Complete", isPresented: $filterManager.showingDownloadCompleteAlert) {
                Button("Apply Now") {
                    Task {
                        await filterManager.applyDownloadedChanges()
                    }
                }
                Button("Later", role: .cancel) {}
            } message: {
                Text(filterManager.downloadCompleteMessage)
            }
            .alert("Category Rule Limit Warning", isPresented: $filterManager.showingCategoryWarningAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(filterManager.categoryWarningMessage)
            }
            .alert("Duplicate Userscripts Found", isPresented: $userScriptManager.showingDuplicatesAlert) {
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
                if filterManager.isLoading && !filterManager.showingApplyProgressSheet && !filterManager.showMissingItemsSheet && !filterManager.showingUpdatePopup {
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
                Task { await ConcurrentLogManager.shared.log("wBlock application appeared.") }
                filterManager.setUserScriptManager(userScriptManager)
                #if os(iOS)
                requestNotificationPermission()
                #endif
            }
            #if os(iOS)
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .background && filterManager.hasUnappliedChanges {
                    scheduleNotification(delay: 1)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .applyWBlockChangesNotification)) { _ in
                print("Received applyWBlockChangesNotification in ContentView.")
                print("Triggering applyChanges from notification observer.")
                filterManager.showingApplyProgressSheet = true
                Task {
                    await filterManager.checkAndEnableFilters(forceReload: true)
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { !dataManager.isLoading && !dataManager.hasCompletedOnboarding },
                set: { _ in }
            )) {
                OnboardingView(filterManager: filterManager)
            }
            #elseif os(macOS)
            .sheet(isPresented: Binding(
                get: { !dataManager.isLoading && !dataManager.hasCompletedOnboarding },
                set: { _ in }
            )) {
                OnboardingView(filterManager: filterManager)
            }
            #endif
    }

    #if os(iOS)
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleNotification(delay: TimeInterval = 1.0) {
        let content = UNMutableNotificationContent()
        content.title = "Psst! You forgot something!"
        content.body = "You have unapplied filter changes in wBlock. Tap to apply them now!"
        content.sound = .default
        content.userInfo = ["action_type": "apply_wblock_changes"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

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
    @Environment(\.dismiss) var dismiss

    @State private var filterName: String = ""
    @State private var filterURLString: String = ""
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 15) {
            Text("Add Custom Filter List")
                .font(.title3)
                .fontWeight(.medium)

            VStack(alignment: .leading) {
                Text("Filter Name (Optional):").font(.caption)
                TextField("e.g., My Ad Block List", text: $filterName)
            }

            VStack(alignment: .leading) {
                Text("Filter URL:").font(.caption)
                TextField("https://example.com/filter.txt", text: $filterURLString)
            }

            Spacer()

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    validateAndAdd()
                }
                .disabled(filterURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding()
        #if os(macOS)
        .frame(width: 400, height: 220)
        #endif
        .alert("Invalid Input", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func validateAndAdd() {
        let trimmedURL = filterURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedURL.isEmpty,
              let url = URL(string: trimmedURL),
              url.scheme != nil,
              url.host != nil else {
            errorMessage = "The URL entered is not valid. Please enter a complete and correct URL (e.g., http:// or https://)."
            showErrorAlert = true
            return
        }

        if filterManager.filterLists.contains(where: { $0.url == url }) {
            errorMessage = "A filter list with this URL already exists."
            showErrorAlert = true
            return
        }

        filterManager.addFilterList(name: filterName, urlString: trimmedURL)
        dismiss()
    }
}
