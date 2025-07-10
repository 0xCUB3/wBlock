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
    @StateObject private var userScriptManager = UserScriptManager()
    @State private var showingAddFilterSheet = false
    @State private var showingLogsView = false
    @State private var showingUserScriptsView = false
    @State private var showOnlyEnabledLists = false
    @Environment(\.scenePhase) var scenePhase

    private var enabledListsCount: Int {
        filterManager.filterLists.filter { $0.isSelected }.count
    }
    
    private var displayableCategories: [FilterListCategory] {
        FilterListCategory.allCases.filter { $0 != .all && $0 != .custom }
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            headerView
            #endif
            
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
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, maxWidth: .infinity,
               minHeight: 500, idealHeight: 650, maxHeight: .infinity)
        #else
        .frame(minWidth: 0, idealWidth: .infinity, maxWidth: .infinity,
               minHeight: 0, idealHeight: .infinity, maxHeight: .infinity)
        #endif
        .sheet(isPresented: $showingAddFilterSheet) {
            AddFilterListView(filterManager: filterManager)
        }
        .sheet(isPresented: $showingLogsView) {
            LogsView()
        }
        .sheet(isPresented: $showingUserScriptsView) {
            UserScriptManagerView(userScriptManager: userScriptManager)
        }
        .sheet(isPresented: $filterManager.showingUpdatePopup) {
            UpdatePopupView(filterManager: filterManager, userScriptManager: userScriptManager, isPresented: $filterManager.showingUpdatePopup)
        }
        .sheet(isPresented: $filterManager.showMissingFiltersSheet) {
            MissingFiltersView(filterManager: filterManager)
        }
        .sheet(isPresented: $filterManager.showingApplyProgressSheet) {
            ApplyChangesProgressView(filterManager: filterManager, isPresented: $filterManager.showingApplyProgressSheet)
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
        .overlay {
            if filterManager.isLoading && !filterManager.showingApplyProgressSheet && !filterManager.showMissingFiltersSheet && !filterManager.showingUpdatePopup {
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
            // Set the UserScriptManager for filter updates
            filterManager.setUserScriptManager(userScriptManager)
            #if os(iOS)
            requestNotificationPermission()
            #endif
        }
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    Task { await filterManager.checkForUpdates() }
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .disabled(filterManager.isLoading)
                .help("Check for filter list updates")
                
                Button {
                    filterManager.checkAndEnableFilters(forceReload: true)
                } label: {
                    Label("Apply Changes", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(filterManager.isLoading || enabledListsCount == 0)
                .help("Apply selected filters and reload Safari")
                
                Button {
                    showingLogsView = true
                } label: {
                    Label("Show Logs", systemImage: "doc.text.magnifyingglass")
                }
                .help("View application logs")
                
                Button {
                    showingUserScriptsView = true
                } label: {
                    Label("User Scripts", systemImage: "doc.text.fill")
                }
                .help("Manage userscripts")
                
                Button {
                    showingAddFilterSheet = true
                } label: {
                    Label("Add Filter", systemImage: "plus")
                }
                .help("Add custom filter list from URL")
                
                Button {
                    showOnlyEnabledLists.toggle()
                } label: {
                    Label("Show Enabled Only", systemImage: showOnlyEnabledLists ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .help("Toggle to show only enabled filter lists")
            }
        }
        #endif
        #if os(iOS)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background && filterManager.hasUnappliedChanges {
                scheduleNotification(delay: 1) // Reduced delay to 1 second
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .applyWBlockChangesNotification)) { _ in
            print("Received applyWBlockChangesNotification in ContentView.")
            // Ensure we are on the main thread for UI updates if needed
            print("Triggering applyChanges from notification observer.")
            filterManager.showingApplyProgressSheet = true // Show progress sheet
            Task {
                await filterManager.checkAndEnableFilters(forceReload: true)
            }
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

    private func scheduleNotification(delay: TimeInterval = 1.0) { // Added delay parameter, default to 1 second
        let content = UNMutableNotificationContent()
        content.title = "Psst! You forgot something!"
        content.body = "You have unapplied filter changes in wBlock. Tap to apply them now!"
        content.sound = .default
        content.userInfo = ["action_type": "apply_wblock_changes"] // Add userInfo for tap action

        // Schedule the notification
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

    #if os(iOS)
    private var headerView: some View {
        HStack {
            Spacer()
            
            HStack(spacing: 12) {
                Button { Task { await filterManager.checkForUpdates() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(filterManager.isLoading)
                
                Button { Task { await filterManager.checkAndEnableFilters(forceReload: true) } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(filterManager.isLoading || enabledListsCount == 0)
                
                Button { showingLogsView = true } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                
                Button { showingUserScriptsView = true } label: {
                    Image(systemName: "doc.text.fill")
                }
                
                Button { showingAddFilterSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    #endif
    
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
                title: "Safari Rules",
                value: filterManager.lastRuleCount.formatted(),
                icon: "shield.lefthalf.filled",
                pillColor: .clear, // Remove global pill color logic
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
        VStack(alignment: .leading, spacing: 8) {
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
                    
                    if !filter.version.isEmpty {
                        Text("Version: \(filter.version)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
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
        }
        .padding(16)
        .contentShape(Rectangle())
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

    // This function is now replaced by using filter.sourceRuleCount
    // private func getRuleCountForFilter(_ filter: FilterList) -> String { ... }
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

