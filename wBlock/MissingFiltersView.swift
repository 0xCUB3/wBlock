//
//  MissingFiltersView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI

struct MissingFiltersView: View {
    @ObservedObject var filterManager: AppFilterManager
    @Environment(\.dismiss) var dismiss
    
    private var progressPercentage: Int {
        Int(round(filterManager.progress * 100))
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header (no redundant subtitle)
            HStack {
                Text(filterManager.isLoading ? "Downloading Missing Filters" : "Missing Filters")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .animation(.easeInOut(duration: 0.3), value: filterManager.isLoading)
                Spacer()
                if !filterManager.isLoading {
                    Button {
                        dismiss()
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
                .frame(height: 150)
                .transition(.opacity)
            } else {
                // Filter list
                List(filterManager.missingFilters, id: \.id) { filter in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(filter.name)
                            .font(.body)
                        if !filter.description.isEmpty {
                            Text(filter.description)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
                #if os(macOS)
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                #else
                .listStyle(.insetGrouped)
                #endif
                .frame(height: 200)
                .transition(.opacity)
            }

            // Buttons
            HStack(spacing: 20) {
                if !filterManager.isLoading {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Download") {
                        Task {
                            await filterManager.downloadMissingFilters()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: filterManager.isLoading)
        }
        .padding()
        .animation(.easeInOut(duration: 0.4), value: filterManager.isLoading)
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 450, maxWidth: 480,
               minHeight: 300, idealHeight: 350, maxHeight: 400)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .frame(minWidth: 0, idealWidth: .infinity, maxWidth: .infinity,
               minHeight: 0, idealHeight: .infinity, maxHeight: .infinity)
        #endif
    }
}