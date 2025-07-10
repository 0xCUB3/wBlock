//
//  UpdatePopupView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI
import wBlockCoreService

struct UpdatePopupView: View {
    @ObservedObject var filterManager: AppFilterManager
    @State private var selectedFilters: Set<UUID>
    @State private var selectedScripts: Set<UUID> = []
    @State private var selectedCategories: Set<FilterListCategory> = []
    @Binding var isPresented: Bool
    
    var userScriptManager: UserScriptManager?
    @State private var scriptsWithUpdates: [UserScript] = []
    
    init(filterManager: AppFilterManager, userScriptManager: UserScriptManager? = nil, isPresented: Binding<Bool>) {
        self.filterManager = filterManager
        self.userScriptManager = userScriptManager
        self._isPresented = isPresented
        self._selectedFilters = State(initialValue: Set(filterManager.availableUpdates.map { $0.id }))
        
        // Initialize selected categories from filters
        var categories = Set<FilterListCategory>()
        for filter in filterManager.availableUpdates {
            categories.insert(filter.category)
        }
        self._selectedCategories = State(initialValue: categories)
    }
    
    private var progressPercentage: Int {
        Int(round(filterManager.progress * 100))
    }
    
    private var hasScriptUpdates: Bool {
        return !scriptsWithUpdates.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) { // Align content to the top leading edge
            // Header (no redundant subtitle)
            HStack {
                Text(filterManager.isLoading ? "Downloading Updates" : "Available Updates")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .animation(.easeInOut(duration: 0.3), value: filterManager.isLoading)
                Spacer()
                if !filterManager.isLoading {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // Filter list or progress view
            if filterManager.isLoading {
                // Download progress view
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        ProgressView(value: filterManager.progress)
                            .progressViewStyle(.linear)
                            .scaleEffect(y: 1.2)
                            .animation(.easeInOut(duration: 0.2), value: filterManager.progress)
                        
                        Text("\(progressPercentage)%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .animation(.easeInOut(duration: 0.2), value: progressPercentage)
                    }
                    .padding(.horizontal)
                    
                    Text("After downloading, filter lists will be applied automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 200)
                .transition(.opacity)
            } else {
                // Filter selection list
                List {
                    // Group filter lists by category
                    let filtersByCategory = Dictionary(grouping: filterManager.availableUpdates) { $0.category }
                    
                    ForEach(FilterListCategory.allCases.filter { category in
                        filtersByCategory[category] != nil || (category == .scripts && !scriptsWithUpdates.isEmpty)
                    }, id: \.self) { category in
                        Section {
                            // Show filters in this category
                            if let filters = filtersByCategory[category] {
                                ForEach(filters, id: \.id) { filter in
                                    HStack {
                                        Image(systemName: selectedFilters.contains(filter.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedFilters.contains(filter.id) ? .blue : .gray)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(filter.name)
                                                .font(.body)
                                            if !filter.description.isEmpty {
                                                Text(filter.description)
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedFilters.contains(filter.id) {
                                            selectedFilters.remove(filter.id)
                                            
                                            // Check if all filters in this category are deselected
                                            let categoryFilters = filtersByCategory[category] ?? []
                                            let selectedCategoryFilters = categoryFilters.filter { selectedFilters.contains($0.id) }
                                            
                                            if selectedCategoryFilters.isEmpty {
                                                selectedCategories.remove(category)
                                            }
                                        } else {
                                            selectedFilters.insert(filter.id)
                                            selectedCategories.insert(category)
                                        }
                                    }
                                }
                            }
                            
                            // Show scripts if in scripts category
                            if category == .scripts && !scriptsWithUpdates.isEmpty {
                                ForEach(scriptsWithUpdates, id: \.id) { script in
                                    HStack {
                                        Image(systemName: selectedScripts.contains(script.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedScripts.contains(script.id) ? .blue : .gray)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(script.name)
                                                .font(.body)
                                            if !script.description.isEmpty {
                                                Text(script.description)
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if selectedScripts.contains(script.id) {
                                            selectedScripts.remove(script.id)
                                            
                                            if selectedScripts.isEmpty {
                                                selectedCategories.remove(.scripts)
                                            }
                                        } else {
                                            selectedScripts.insert(script.id)
                                            selectedCategories.insert(.scripts)
                                        }
                                    }
                                }
                            }
                        } header: {
                            // Category header with toggle for all items in category
                            HStack {
                                Text(category.rawValue)
                                    .font(.headline)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { selectedCategories.contains(category) },
                                    set: { isSelected in
                                        if isSelected {
                                            // Select all items in category
                                            selectedCategories.insert(category)
                                            if category == .scripts {
                                                selectedScripts = Set(scriptsWithUpdates.map { $0.id })
                                            } else if let filters = filtersByCategory[category] {
                                                for filter in filters {
                                                    selectedFilters.insert(filter.id)
                                                }
                                            }
                                        } else {
                                            // Deselect all items in category
                                            selectedCategories.remove(category)
                                            if category == .scripts {
                                                selectedScripts.removeAll()
                                            } else if let filters = filtersByCategory[category] {
                                                for filter in filters {
                                                    selectedFilters.remove(filter.id)
                                                }
                                            }
                                        }
                                    }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                            }
                        }
                    }
                }
                #if os(macOS)
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(minHeight: 150, maxHeight: 300) // Keep frame for macOS
                #else
                .listStyle(.plain) // Use plain list style for iOS, no fixed frame
                #endif
                .transition(.opacity)
            }

            // Buttons
            HStack(spacing: 20) {
                if !filterManager.isLoading {
                    Spacer()
                    Button("Download") {
                        Task {
                            // Handle filter list updates
                            let filtersToUpdate = filterManager.availableUpdates.filter { selectedFilters.contains($0.id) }
                            if !filtersToUpdate.isEmpty {
                                await filterManager.downloadSelectedFilters(filtersToUpdate)
                            }
                            
                            // Handle script updates
                            if let _ = userScriptManager, !selectedScripts.isEmpty {
                                let scriptsToUpdate = scriptsWithUpdates.filter { selectedScripts.contains($0.id) }
                                if !scriptsToUpdate.isEmpty {
                                    _ = await filterManager.filterUpdater.updateSelectedScripts(scriptsToUpdate) { progress in
                                        // Update progress for script downloads
                                        if filtersToUpdate.isEmpty {
                                            filterManager.progress = progress
                                        }
                                    }
                                }
                            }
                        }
                    }
                    #if os(macOS)
                    .buttonStyle(.borderedProminent)
                    #else
                    // Default button style for iOS
                    #endif
                    .disabled(selectedFilters.isEmpty && selectedScripts.isEmpty)
                    .keyboardShortcut(.defaultAction)
                    Spacer()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: filterManager.isLoading)
        }
        .padding()
        .animation(.easeInOut(duration: 0.4), value: filterManager.isLoading)
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 450, maxWidth: 480,
               minHeight: 300, idealHeight: 350, maxHeight: 400)
        #else
        // Ensure the VStack takes up available space and aligns content to the top
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #endif
        .onAppear {
            if let scriptManager = userScriptManager {
                Task {
                    // Check for available script updates
                    scriptsWithUpdates = await filterManager.filterUpdater.checkForScriptUpdates(scripts: scriptManager.userScripts)
                    
                    // Initialize selected scripts
                    selectedScripts = Set(scriptsWithUpdates.map { $0.id })
                    
                    // Add scripts category to selected categories if there are script updates
                    if !scriptsWithUpdates.isEmpty {
                        selectedCategories.insert(.scripts)
                    }
                }
            }
        }
    }
}
