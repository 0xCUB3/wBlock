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
    @EnvironmentObject var updateController: UpdateController

    @StateObject private var windowDelegate = WindowDelegate()
    @State private var selectedCategory: FilterListCategory = .all
    @State private var showingLogs = false
    @State private var showingSettings = false
    @State private var showingAddFilterSheet = false

    var body: some View {
        NavigationSplitView {
            List(FilterListCategory.allCases, id: \.self, selection: $selectedCategory) { category in
                Text(category.rawValue)
                    .tag(category)
            }
            .navigationTitle("Categories")
            .listStyle(SidebarListStyle())
        } detail: {
            FilterListContentView(selectedCategory: selectedCategory, filterListManager: filterListManager)
                .navigationTitle(selectedCategory.rawValue)
                .toolbar {
                    toolbarContent
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
        .sheet(isPresented: $showingAddFilterSheet) {
            AddCustomFilterView(filterListManager: filterListManager)
        }
        .sheet(isPresented: $filterListManager.showMissingFiltersSheet) {
            MissingFiltersView(filterListManager: filterListManager)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
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
            filterListManager.checkForEnabledFilters()
        }
    }

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

struct FilterListContentView: View {
    let selectedCategory: FilterListCategory
    @ObservedObject var filterListManager: FilterListManager

    var body: some View {
        VStack {
            if selectedCategory == .all {
                allFiltersView
            } else if selectedCategory == .custom {
                customFiltersView
            } else {
                categoryFiltersView
            }
        }
    }

    // Define separate computed properties for each condition
    var allFiltersView: some View {
        List {
            ForEach(FilterListCategory.allCases.filter { $0 != .all }, id: \.self) { category in
                if !filterListManager.filterLists(for: category).isEmpty {
                    Section(header: Text(category.rawValue)) {
                        ForEach(filterListManager.filterLists(for: category)) { filter in
                            FilterRowView(filter: filter, filterListManager: filterListManager)
                        }
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
    }

    var customFiltersView: some View {
        List(filterListManager.customFilterLists) { filter in
            FilterRowView(filter: filter, filterListManager: filterListManager)
        }
        .listStyle(PlainListStyle())
    }

    var categoryFiltersView: some View {
        List(filterListManager.filterLists(for: selectedCategory)) { filter in
            FilterRowView(filter: filter, filterListManager: filterListManager)
        }
        .listStyle(PlainListStyle())
    }
}

struct FilterRowView: View {
    let filter: FilterList
    @ObservedObject var filterListManager: FilterListManager

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filter.name)
                if !filter.version.isEmpty {
                    Text("Version: \(filter.version)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if !filter.description.isEmpty {
                    Text(filter.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { filter.isSelected },
                set: { _ in filterListManager.toggleFilterListSelection(id: filter.id) }
            ))
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            .labelsHidden()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            filterListManager.toggleFilterListSelection(id: filter.id)
        }
        .contextMenu {
            if filter.category == .custom {
                Button("Remove Filter") {
                    filterListManager.removeCustomFilterList(filter)
                }
            }
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
        NSApplication.shared.terminate(nil)
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Logs")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

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

struct AddCustomFilterView: View {
    @ObservedObject var filterListManager: FilterListManager
    @Environment(\.presentationMode) var presentationMode

    @State private var filterName: String = ""
    @State private var filterURLString: String = ""
    @State private var filterDescription: String = "" // Optional description

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Custom Filter")
                .font(.largeTitle)
                .fontWeight(.bold)

            TextField("Filter Name", text: $filterName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            TextField("Filter URL", text: $filterURLString)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            TextField("Description (Optional)", text: $filterDescription)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            Spacer()

            HStack(spacing: 20) {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Cancel")
                        .fontWeight(.semibold)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    if let url = URL(string: filterURLString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        filterListManager.addCustomFilterList(
                            name: filterName.trimmingCharacters(in: .whitespacesAndNewlines),
                            url: url,
                            description: filterDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        // Optionally, present an alert for invalid URL
                    }
                }) {
                    Text("Add")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(filterName.isEmpty || filterURLString.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 450, height: 350)
        .background(Color(.windowBackgroundColor))
    }
}
