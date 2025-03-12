import SwiftUI
import SwiftData

struct ContentView: View {
    @ObservedObject var filterListManager: FilterListManager

    @State private var selectedCategory: FilterListCategory? = .all
    @State private var showingLogs = false
    @State private var showingSettings = false
    @State private var showingAddFilterSheet = false

    var body: some View {
        NavigationSplitView {
            List(FilterListCategory.allCases, id: \.self, selection: $selectedCategory) { category in
                NavigationLink(category.rawValue, value: category)
            }
            .navigationTitle("Categories")
            .listStyle(.sidebar)
        } detail: {
            if let selectedCategory = selectedCategory {
                FilterListContentView(selectedCategory: selectedCategory, filterListManager: filterListManager)
                     .navigationTitle(selectedCategory.rawValue)
                     .toolbar {
                         toolbarContent
                     }
            } else {
                Text("Select Category")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $filterListManager.showingUpdatePopup) {
            UpdatePopupView(filterListManager: filterListManager, isPresented: $filterListManager.showingUpdatePopup)
        }
        .sheet(isPresented: $showingLogs) {
            LogsView(logs: filterListManager.logs)
        }
        .sheet(isPresented: $showingAddFilterSheet) {
            AddCustomFilterView(filterListManager: filterListManager)
        }
        .sheet(isPresented: $filterListManager.showMissingFiltersSheet) {
            MissingFiltersView(filterListManager: filterListManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView() // No changes needed within SettingsView itself
                .environmentObject(filterListManager) // Pass the environment object
        }
        .alert("Enable Recommended Filters?", isPresented: $filterListManager.showRecommendedFiltersAlert) {
            Button("Enable") {
                filterListManager.checkForEnabledFilters()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No filters are currently enabled. Would you like to enable the recommended filters?")
        }
        .alert("Reset to Default Lists?", isPresented: $filterListManager.showResetToDefaultAlert) {
            Button("Reset", role: .destructive) {
                filterListManager.resetToDefaultLists()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset all filter selections to the recommended defaults. Are you sure?")
        }
        .alert("No Updates Found", isPresented: $filterListManager.showingNoUpdatesAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button(action: {
                Task {
                    await filterListManager.checkAndEnableFilters()
                }
            }) {
                Image(systemName: "tray.and.arrow.down.fill")
            }
            .help("Apply Changes")
            .disabled(!filterListManager.hasUnappliedChanges)
            
            Button(action: {
                showingAddFilterSheet = true
            }) {
                Label("Add Filter", systemImage: "plus")
            }
            .help("Add Custom Filter")
            
            Button(action: {
                Task {
                    await filterListManager.checkForUpdates()
                }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Update Filters")
            
            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            
            Menu {
                Button("Show Logs") {
                    showingLogs = true
                }
                Button("Reset to Default") {
                    filterListManager.showResetToDefaultAlert = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("More Options")
        }
    }
}
