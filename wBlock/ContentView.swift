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
    @State private var showingAddFilterSheet = false
    @State private var showingLogsView = false
    @State private var showOnlyEnabledLists = false
    @Environment(\.scenePhase) var scenePhase

    // For category-specific limit warnings/errors
    @State private var showingCategoryLimitInfoAlert = false
    @State private var categoryLimitInfoTitle = ""
    @State private var categoryLimitInfoMessage = ""
    
    @State private var showingCategoryResetConfirmationAlert = false
    @State private var categoryToResetForConfirmation: FilterListCategory? = nil


    private var enabledListsCount: Int {
        // Count unique selected filters from both lists
        let selectedStandard = filterManager.filterLists.filter { $0.isSelected }
        let selectedCustom = filterManager.customFilterLists.filter { $0.isSelected }
        
        var uniqueSelected: [FilterList] = []
        let allSelected = selectedStandard + selectedCustom
        for filter in allSelected {
            if !uniqueSelected.contains(where: { $0.id == filter.id }) {
                uniqueSelected.append(filter)
            }
        }
        return uniqueSelected.count
    }
    
    private var displayableCategories: [FilterListCategory] {
        // Exclude .all, and handle .custom separately if needed or include it here
        FilterListCategory.allCases.filter { $0 != .all }
    }
    
    // Helper to get target info for the current platform
    private func getPlatformSpecificTargets() -> [ContentBlockerTargetInfo] {
        let currentPlatform: Platform = {
            #if os(macOS)
            return .macOS
            #else
            return .iOS
            #endif
        }()
        return filterManager.allContentBlockerTargets.filter { $0.platform == currentPlatform }
    }


    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            headerView
                .padding(.bottom, 8) // Add some space below header on iOS
            #endif
            
            ScrollView {
                VStack(spacing: 20) {
                    statsCardsView // Shows overall Safari rules applied successfully
                    
                    LazyVStack(spacing: 16) {
                        ForEach(displayableCategories) { category in
                            let listsForCategory = self.listsForCategory(category)
                            // Only show section if there are lists OR if it's a custom category that might be added to
                            if !listsForCategory.isEmpty || category == .custom {
                                filterSectionView(category: category, filters: listsForCategory)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 20)
                }
                .padding(.vertical)
            }
            #if os(iOS)
            .padding(.horizontal, 0) // Let ScrollView handle full width
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
        .sheet(isPresented: $filterManager.showingUpdatePopup) {
            UpdatePopupView(filterManager: filterManager, isPresented: $filterManager.showingUpdatePopup)
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
        .alert("Rule Limit Information", isPresented: $showingCategoryLimitInfoAlert) { // For warning triangle tap
            Button("OK", role: .cancel) {}
        } message: {
            Text(categoryLimitInfoMessage)
        }
        .alert("Reset Category Filters?", isPresented: $showingCategoryResetConfirmationAlert) { // For reset button tap
            Button("Reset \(categoryToResetForConfirmation?.rawValue ?? "Category")", role: .destructive) {
                if let category = categoryToResetForConfirmation {
                    Task {
                        await filterManager.resetFiltersForCategory(category)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will deselect all filters in the '\(categoryToResetForConfirmation?.rawValue ?? "selected")' category. You'll need to click 'Apply Changes' afterwards.")
        }
        .alert("Rule Limit Exceeded", isPresented: $filterManager.showingPostApplyLimitIssuesAlert) { // After applyChanges
            Button("OK", role: .cancel) {}
        } message: {
            Text(filterManager.postApplyLimitIssuesMessage)
        }
        .overlay {
            if filterManager.isLoading && !filterManager.showingApplyProgressSheet && !filterManager.showMissingFiltersSheet && !filterManager.showingUpdatePopup {
                ZStack {
                    Color.black.opacity(0.1).ignoresSafeArea()
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(filterManager.overallProgressDescription) // Use overall description
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
                    Task { await filterManager.checkAndEnableFilters() }
                } label: {
                    Label("Apply Changes", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(filterManager.isLoading || enabledListsCount == 0 || !filterManager.hasUnappliedChanges)
                .help("Apply selected filters and reload Safari")
                
                Button {
                    showingLogsView = true
                } label: {
                    Label("Show Logs", systemImage: "doc.text.magnifyingglass")
                }
                .help("View application logs")
                
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
                scheduleNotification(delay: 1)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .applyWBlockChangesNotification)) { _ in
            if filterManager.hasUnappliedChanges {
                filterManager.showingApplyProgressSheet = true
                Task {
                    await filterManager.applyChanges()
                }
            }
        }
        #endif
    }
    
    #if os(iOS)
    private func requestNotificationPermission() { /* ... as before ... */ }
    private func scheduleNotification(delay: TimeInterval = 1.0) { /* ... as before ... */ }
    #endif

    #if os(iOS)
    private var headerView: some View {
        HStack {
            Spacer()
            HStack(spacing: 16) { // Increased spacing for iOS
                Button { Task { await filterManager.checkForUpdates() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.disabled(filterManager.isLoading)
                
                Button { Task { await filterManager.checkAndEnableFilters() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }.disabled(filterManager.isLoading || enabledListsCount == 0 || !filterManager.hasUnappliedChanges)
                
                Button { showingLogsView = true } label: { Image(systemName: "doc.text.magnifyingglass") }
                Button { showingAddFilterSheet = true } label: { Image(systemName: "plus") }
            }
            .font(.title2) // Make icons a bit larger on iOS
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar) // iOS-like background for the header
    }
    #endif
    
    private var statsCardsView: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Enabled Lists",
                value: "\(enabledListsCount)",
                icon: "list.bullet.rectangle.portrait",
                pillColor: .clear,
                valueColor: .primary
            )
            StatCard(
                title: "Safari Rules",
                value: filterManager.lastRuleCount.formatted(),
                icon: "shield.lefthalf.filled",
                pillColor: .clear,
                valueColor: .primary
            )
        }
        .padding(.horizontal)
    }
    
    private func listsForCategory(_ category: FilterListCategory) -> [FilterList] {
        let combinedLists = filterManager.filterLists + filterManager.customFilterLists
        let uniqueLists = combinedLists.reduce(into: [FilterList]()) { result, filter in
            if !result.contains(where: { $0.id == filter.id }) {
                result.append(filter)
            }
        }
        return uniqueLists.filter { $0.category == category && (!showOnlyEnabledLists || $0.isSelected) }
    }
    
    private func filterSectionView(category: FilterListCategory, filters: [FilterList]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.rawValue)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // --- Rule Limit Warning/Error Display ---
                let platformTargets = getPlatformSpecificTargets()
                let targetsForThisCategory = platformTargets.filter { $0.categories.contains(category) }

                // Assuming for UI simplicity, we primarily look at the first target found for this category
                // or you might sum/average if multiple targets share a UI category display.
                if let primaryTarget = targetsForThisCategory.first {
                    let currentCount = filterManager.lastAppliedRuleCountsPerTarget[primaryTarget.jsonFileName] ?? 0
                    let limit = primaryTarget.ruleLimit
                    let percentageUsed = limit > 0 ? (Double(currentCount) / Double(limit)) * 100.0 : 0.0
                    
                    if filterManager.targetsThatExceededLimit.contains(primaryTarget.jsonFileName) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.octagon.fill")
                                .foregroundColor(.red)
                            Text("Limit Exceeded!")
                                .font(.caption)
                                .foregroundColor(.red)
                            Button("Reset") {
                                categoryToResetForConfirmation = category
                                showingCategoryResetConfirmationAlert = true
                            }
                            .font(.caption)
                            .buttonStyle(.borderless) // or .link
                            #if os(iOS)
                            .padding(.leading, 4)
                            #endif
                        }
                    } else if currentCount > 0 && percentageUsed >= 90.0 { // Warning threshold (e.g., 90%)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .onTapGesture {
                                categoryLimitInfoTitle = "\(category.rawValue) Rule Limit"
                                categoryLimitInfoMessage = "Using \(currentCount) of \(limit) available rules (\(String(format: "%.0f%%", percentageUsed))). Approaching the Safari limit for this category."
                                showingCategoryLimitInfoAlert = true
                            }
                    }
                }
                // --- End Rule Limit Display ---
            }
            .padding(.horizontal, 4)
            
            if !filters.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(filters.enumerated()), id: \.element.id) { index, filter in
                        filterRowView(filter: filter)
                        if index < filters.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            } else if category == .custom {
                 Text("No custom filters added yet. Click the '+' button to add one.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            }
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
                        Text("(Counting...)") // Or "File missing" if more accurate
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
                    set: { _ in // The actual toggle is handled by the manager
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
                    filterManager.removeCustomFilterList(filter) // Use specific custom removal
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
        .task(id: filter.id) { // For on-demand count updates if a file exists but count is missing
            if filter.sourceRuleCount == nil && filterManager.doesFilterFileExist(filter) {
                 await filterManager.updateVersionsAndCounts() // This will update counts for lists where file exists
            }
        }
    }
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
