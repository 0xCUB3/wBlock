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
    @State private var selectedCategory: FilterListCategory = .all
    @State private var selectedFilterList: FilterList?
    @State private var showingMissingFiltersAlert = false
    @State private var showingLogs = false
    
    init(filterListManager: FilterListManager) {
        self._filterListManager = ObservedObject(wrappedValue: filterListManager)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedCategory) {
                ForEach(FilterListCategory.allCases) { category in
                    NavigationLink(value: category) {
                        Text(category.rawValue)
                    }
                }
            }
            .navigationTitle("Categories")
        } detail: {
            VStack {
                List {
                    ForEach(filterListManager.filterLists(for: selectedCategory)) { filterList in
                        HStack {
                            Text(filterList.name)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { filterList.isSelected },
                                set: { _ in filterListManager.toggleFilterListSelection(id: filterList.id) }
                            ))
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                        }
                        .padding(.vertical, 8) // Makes the row thicker
                        .popover(isPresented: Binding(
                            get: { selectedFilterList?.id == filterList.id },
                            set: { _ in selectedFilterList = nil }
                        )) {
                            FilterListDetailView(filterList: filterList)
                        }
                        .onTapGesture {
                            selectedFilterList = filterList
                        }
                    }
                }
                .navigationTitle(selectedCategory.rawValue)
                
                if filterListManager.isUpdating {
                    VStack {
                        ProgressView("Updating filters...", value: filterListManager.progress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding()
                        
                        ScrollView {
                            Text(filterListManager.logs)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                        }
                        .frame(height: 100)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .padding()
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(10)
                    .shadow(radius: 10)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply Changes") {
                        Task {
                            await applyChanges()
                        }
                    }
                    .disabled(filterListManager.isUpdating)
                }
                ToolbarItem(placement: .automatic) {
                    Button("Check for Updates") {
                        Task {
                            await filterListManager.checkForUpdates()
                        }
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button("View Logs") {
                        showingLogs = true
                    }
                }
            }
            
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 600, height: 500)
        .alert("Missing Filters", isPresented: $showingMissingFiltersAlert) {
            Button("Update") {
                Task {
                    await filterListManager.updateMissingFilters()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The following filters are missing: \(missingFiltersNames). Would you like to update them?")
        }
        .sheet(isPresented: $showingLogs) {
            LogsView(logs: filterListManager.logs)
        }
        .sheet(isPresented: $filterListManager.showingUpdatePopup) {
            UpdatePopupView(filterListManager: filterListManager, isPresented: $filterListManager.showingUpdatePopup)
        }
    }
    
    var missingFiltersNames: String {
        filterListManager.missingFilters.map { $0.name }.joined(separator: ", ")
    }
    
    func applyChanges() async {
        filterListManager.checkAndEnableFilters()
        if !filterListManager.missingFilters.isEmpty {
            showingMissingFiltersAlert = true
        } else {
            await filterListManager.applyChanges()
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

struct LogsView: View {
    let logs: String
    
    var body: some View {
        VStack {
            Text("Logs")
                .font(.title)
                .padding()
            ScrollView {
                Text(logs)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
        }
        .frame(width: 400, height: 350)
    }
}
