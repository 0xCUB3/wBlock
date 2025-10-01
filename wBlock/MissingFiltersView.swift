//
//  MissingFiltersView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI
import wBlockCoreService

struct MissingFiltersView: View {
    @ObservedObject var filterManager: AppFilterManager
    @Environment(\.dismiss) var dismiss
    
    private var progressPercentage: Int {
        Int(round(filterManager.progress * 100))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            SheetHeader(
                title: filterManager.isLoading ? "Downloading Missing Filters" : "Missing Filters",
                isLoading: filterManager.isLoading
            ) {
                dismiss()
            }
            .animation(.easeInOut(duration: 0.3), value: filterManager.isLoading)

            // Filter list or progress view
            if filterManager.isLoading {
                // Download progress view
                ProgressViewWithStatus(
                    progress: Double(filterManager.progress),
                    statusText: "\(progressPercentage)%",
                    description: "After downloading, filter lists will be applied automatically."
                )
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
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                }
                #if os(macOS)
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(height: 200)
                #else
                .listStyle(.inset)
                .frame(maxHeight: .infinity)
                #endif
                .transition(.opacity)
            }

            // Buttons
            if !filterManager.isLoading {
                SheetBottomToolbar {
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
        }
        #if os(macOS)
        .frame(width: 400)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SheetDesign.cornerRadius))
        #endif
    }
}