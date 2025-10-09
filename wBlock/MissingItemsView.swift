//
//  MissingItemsView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI
import wBlockCoreService

struct MissingItemsView: View {
    @ObservedObject var filterManager: AppFilterManager
    @Environment(\.dismiss) var dismiss

    private var progressPercentage: Int {
        Int(round(filterManager.progress * 100))
    }

    private var titleText: String {
        let filterCount = filterManager.missingFilters.count
        let scriptCount = filterManager.missingUserScripts.count

        var parts: [String] = []
        if filterCount > 0 {
            parts.append("\(filterCount) filter\(filterCount == 1 ? "" : "s")")
        }
        if scriptCount > 0 {
            parts.append("\(scriptCount) userscript\(scriptCount == 1 ? "" : "s")")
        }

        if parts.isEmpty {
            return "Missing Items"
        } else {
            return parts.joined(separator: " + ") + " missing"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            SheetHeader(
                title: filterManager.isLoading ? "Downloading Missing Items" : titleText,
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
                    description: "After downloading, items will be applied automatically."
                )
            } else {
                // Combined list
                List {
                    if !filterManager.missingFilters.isEmpty {
                        Section(header: Text("Filters").font(.caption).foregroundColor(.secondary)) {
                            ForEach(filterManager.missingFilters, id: \.id) { filter in
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
                        }
                    }

                    if !filterManager.missingUserScripts.isEmpty {
                        Section(header: Text("Userscripts").font(.caption).foregroundColor(.secondary)) {
                            ForEach(filterManager.missingUserScripts, id: \.id) { script in
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
                                .padding(.vertical, 4)
                            }
                        }
                    }
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
                            await filterManager.downloadMissingItems()
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