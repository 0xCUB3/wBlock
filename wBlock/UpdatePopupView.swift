//
//  UpdatePopupView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI

struct UpdatePopupView: View {
    @ObservedObject var filterManager: AppFilterManager
    @State private var selectedFilters: Set<UUID>
    @Binding var isPresented: Bool
    
    init(filterManager: AppFilterManager, isPresented: Binding<Bool>) {
        self.filterManager = filterManager
        self._isPresented = isPresented
        self._selectedFilters = State(initialValue: Set(filterManager.availableUpdates.map { $0.id }))
    }
    
    private var progressPercentage: Int {
        Int(round(filterManager.progress * 100))
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
                List(filterManager.availableUpdates, id: \.id) { filter in
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
                        } else {
                            selectedFilters.insert(filter.id)
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
                            let filtersToUpdate = filterManager.availableUpdates.filter { selectedFilters.contains($0.id) }
                            await filterManager.downloadSelectedFilters(filtersToUpdate)
                        }
                    }
                    #if os(macOS)
                    .buttonStyle(.borderedProminent)
                    #else
                    // Default button style for iOS
                    #endif
                    .disabled(selectedFilters.isEmpty)
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
    }
}