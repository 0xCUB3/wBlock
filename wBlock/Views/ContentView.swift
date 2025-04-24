//
//  ContentView.swift
//  wBlock Origin
//
//  Created by Alexander Skula on 7/17/24.
//

import SwiftUI
import SwiftData

struct ContentViewCommandState {
    var refresh: () -> Void = {}
    var applyChanges: () -> Void = {}
    var showSettings: () -> Void = {}
    var showLogs: () -> Void = {}
    var addCustomFilter: () -> Void = {}
    var toggleOnlyEnabled: () -> Void = {}
    var resetToDefault: () -> Void = {}
    var showCheatSheet: () -> Void = {}
}

struct ContentView: View {
    @ObservedObject var filterListManager: FilterListManager
    @EnvironmentObject var updateController: UpdateController

    @StateObject private var windowDelegate = WindowDelegate()
    @State private var showingLogs = false
    @State private var showingSettings = false
    @State private var showingAddFilterSheet = false
    @State private var showOnlyEnabledFilters = false
    @State private var showingCheatSheet = false

    @Binding var commandState: ContentViewCommandState

    var body: some View {
        VStack {
            FilterListContentView(selectedCategory: .all, filterListManager: filterListManager, showOnlyEnabledFilters: $showOnlyEnabledFilters)
                .navigationTitle("wBlock")
                .toolbar {
                    toolbarContent
                }
        }
        .frame(width: 700, height: 500)
        .sheet(isPresented: $filterListManager.showingUpdatePopup) {
            UpdatePopupView(filterListManager: filterListManager, isPresented: $filterListManager.showingUpdatePopup)
        }
        .sheet(isPresented: $showingLogs) {
            LogsView()
        }
        .sheet(isPresented: $showingAddFilterSheet) {
            AddCustomFilterView(filterListManager: filterListManager)
        }
        .sheet(isPresented: $filterListManager.showMissingFiltersSheet) {
            MissingFiltersView(filterListManager: filterListManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingCheatSheet) {
            KeyboardShortcutCheatSheetView()
        }
        .alert("Enable Recommended Filters?", isPresented: $filterListManager.showRecommendedFiltersAlert) {
            Button("Enable") {
                filterListManager.checkForEnabledFilters()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No filters are currently enabled. Would you like to enable the recommended filters?")
        }
        .alert("Unapplied Changes", isPresented: $windowDelegate.shouldShowExitAlert) {
            Button("Apply Changes") {
                Task {
                    await filterListManager.applyChanges()
                    NSApplication.shared.terminate(nil)
                }
            }
            Button("Exit Without Applying") {
                NSApplication.shared.terminate(nil)
            }
            Button("Cancel", role: .cancel) {
                // Do nothing, just dismiss the alert
            }
        } message: {
            Text("You have unapplied changes. Do you want to apply them before exiting?")
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
        .onAppear {
            windowDelegate.hasUnappliedChanges = { filterListManager.hasUnappliedChanges }
            DispatchQueue.main.async {
                NSApplication.shared.windows.first?.delegate = windowDelegate
            }
            // Connect menu shortcuts when View appears
            commandState.refresh = {
                Task { await filterListManager.checkForUpdates() }
            }
            commandState.applyChanges = {
                Task { await filterListManager.checkAndEnableFilters() }
            }
            commandState.showSettings = {
                showingSettings = true
            }
            commandState.showLogs = {
                showingLogs = true
            }
            commandState.addCustomFilter = {
                showingAddFilterSheet = true
            }
            commandState.toggleOnlyEnabled = {
                showOnlyEnabledFilters.toggle()
            }
            commandState.resetToDefault = {
                filterListManager.showResetToDefaultAlert = true
            }
            commandState.showCheatSheet = {
                showingCheatSheet = true
            }
        }
    }

    // Use a computed property for ToolbarContent
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                Task {
                    await filterListManager.checkAndEnableFilters()
                }
            }) {
                Image(systemName: "tray.and.arrow.down.fill")
            }
            .help("Apply Changes")
            .disabled(!filterListManager.hasUnappliedChanges)
        }
        ToolbarItem(placement: .automatic) {
            Button(action: {
                showingAddFilterSheet = true
            }) {
                Label("Add Filter", systemImage: "plus")
            }
            .help("Add Custom Filter")
        }
        ToolbarItem(placement: .automatic) {
            Button(action: {
                Task {
                    await filterListManager.checkForUpdates()
                }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Update Filters")
        }
        ToolbarItem(placement: .automatic) {
            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }

        ToolbarItem(placement: .automatic) {
            Button(action: {
                showOnlyEnabledFilters.toggle() // Toggle the state
            }) {
                Image(systemName: showOnlyEnabledFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .help(showOnlyEnabledFilters ? "Show All Filters" : "Show Only Enabled Filters")
        }

        ToolbarItem(placement: .automatic) {
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

    init(
        filterListManager: FilterListManager,
        commandState: Binding<ContentViewCommandState>
    ) {
        self.filterListManager = filterListManager
        self._commandState = commandState
    }
}
