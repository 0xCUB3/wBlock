//
//  UpdatePopupView.swift
//  wBlock
//
//  Created by Alexander Skula on 7/18/24.
//

import SwiftUI

struct UpdatePopupView: View {
    @ObservedObject var filterListManager: FilterListManager
    @State private var selectedFilters: Set<UUID>
    @Binding var isPresented: Bool
    
    init(filterListManager: FilterListManager, isPresented: Binding<Bool>) {
        self.filterListManager = filterListManager
        self._isPresented = isPresented
        self._selectedFilters = State(initialValue: Set(filterListManager.availableUpdates.map { $0.id }))
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Available Updates")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Select the filters you want to update:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            List(filterListManager.availableUpdates, id: \.id) { filter in
                HStack {
                    Image(systemName: selectedFilters.contains(filter.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedFilters.contains(filter.id) ? .blue : .gray)
                    Text(filter.name)
                        .font(.body)
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
            .listStyle(PlainListStyle())
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(10)
            .frame(height: filterListManager.isUpdating ? 225 : 300)

            // Show the progress bar below the list while updating
            if filterListManager.isUpdating {
                VStack(spacing: 8) {
                    ProgressView(value: filterListManager.progress, total: 1.0) {
                        Text("Updating selected filters…")
                    }
                    .padding(.horizontal)
                    
                    Text("\(Int(filterListManager.progress * 100))% complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 20) {
                Button(action: {
                    isPresented = false
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
                    Task {
                        let filtersToUpdate = filterListManager.availableUpdates.filter { selectedFilters.contains($0.id) }
                        await filterListManager.updateSelectedFilters(filtersToUpdate)
                        isPresented = false
                    }
                }) {
                    Text("Update Selected")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                // Disable while updating or if none are selected
                .disabled(filterListManager.isUpdating || selectedFilters.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 500)
        .background(Color(.windowBackgroundColor))
    }
}
