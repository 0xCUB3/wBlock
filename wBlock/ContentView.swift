//
//  ContentView.swift
//  wBlock Origin
//
//  Created by Alexander Skula on 7/17/24.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @ObservedObject var filterListManager: FilterListManager
    @StateObject private var windowDelegate = WindowDelegate()
    @State private var selectedCategory: FilterListCategory = .all
    @State private var showingLogs = false

    var body: some View {
        NavigationSplitView {
            List(FilterListCategory.allCases, id: \.self, selection: $selectedCategory) { category in
                Text(category.rawValue)
                    .tag(category)
            }
            .navigationTitle("Categories")
            .listStyle(SidebarListStyle())
        } detail: {
            VStack {
                List {
                    ForEach(filterListManager.filterLists(for: selectedCategory)) { filter in
                        HStack {
                            Text(filter.name)
                                .padding(.vertical, 8)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { filter.isSelected },
                                set: { _ in filterListManager.toggleFilterListSelection(id: filter.id) }
                            ))
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle(selectedCategory.rawValue)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply Changes") {
                        Task {
                            await filterListManager.checkAndEnableFilters()
                        }
                    }
                    .disabled(!filterListManager.hasUnappliedChanges)
                }
                ToolbarItem(placement: .automatic) {
                    Button("Check for Updates") {
                        Task {
                            await filterListManager.checkForUpdates()
                        }
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Show Logs") {
                        showingLogs = true
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 700, height: 500)
        .sheet(isPresented: $filterListManager.showingUpdatePopup) {
            UpdatePopupView(filterListManager: filterListManager, isPresented: $filterListManager.showingUpdatePopup)
        }
        .sheet(isPresented: $showingLogs) {
            LogsView(logs: filterListManager.logs)
        }
        .sheet(isPresented: $filterListManager.showMissingFiltersSheet) {
            MissingFiltersView(filterListManager: filterListManager)
        }
        .alert("Enable Recommended Filters?", isPresented: $filterListManager.showRecommendedFiltersAlert) {
            Button("Enable") {
                filterListManager.enableRecommendedFilters()
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
        .onAppear {
            windowDelegate.hasUnappliedChanges = { filterListManager.hasUnappliedChanges }
            DispatchQueue.main.async {
                NSApplication.shared.windows.first?.delegate = windowDelegate
            }
            filterListManager.checkForEnabledFilters()
        }
    }
}

struct FilterListDetailView: View {
    let filterList: FilterList
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(filterList.name)
                .font(.title)
            Text("Category: \(filterList.category.rawValue)")
            VStack(alignment: .leading, spacing: 5) {
                Text("URL:")
                Link(filterList.url.absoluteString, destination: filterList.url)
                    .foregroundColor(.blue)
            }
            Text("Status: \(filterList.isSelected ? "Enabled" : "Disabled")")
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}

class WindowDelegate: NSObject, NSWindowDelegate, ObservableObject {
    @Published var shouldShowExitAlert = false
    var hasUnappliedChanges: () -> Bool = { false }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if hasUnappliedChanges() {
            shouldShowExitAlert = true
            return false
        }
        return true
    }
}

struct MissingFiltersView: View {
    @ObservedObject var filterListManager: FilterListManager
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 20) {
            Text("Missing Filters")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("The following filters need to be downloaded:")
                .font(.headline)
            
            List(filterListManager.missingFilters, id: \.id) { filter in
                Text(filter.name)
                    .padding(.vertical, 4)
            }
            .frame(height: 200)
            .background(Color(.windowBackgroundColor))
            .cornerRadius(8)
            
            Button(action: {
                Task {
                    await filterListManager.updateMissingFilters()
                    presentationMode.wrappedValue.dismiss()
                }
            }) {
                Text("Update Missing Filters")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .frame(width: 400, height: 400)
        .background(Color(.windowBackgroundColor))
    }
}

struct LogsView: View {
    let logs: String
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Logs")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            ScrollView {
                TextEditor(text: .constant(logs))
                    .font(.system(.body, design: .monospaced))
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
            }
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .frame(width: 600, height: 400)
        .background(Color(.windowBackgroundColor))
    }
}
