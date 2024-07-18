//
//  UpdatePopupView.swift
//  wBlock
//
//  Created by Alexander Skula on 7/18/24.
//

import SwiftUI

struct UpdatePopupView: View {
    @ObservedObject var filterListManager: FilterListManager
    @State private var selectedFilters: Set<UUID> = []
    @Binding var isPresented: Bool

    var body: some View {
        VStack {
            Text("Available Updates")
                .font(.title)
                .padding()

            List(filterListManager.availableUpdates, id: \.id) { filter in
                HStack {
                    Text(filter.name)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { selectedFilters.contains(filter.id) },
                        set: { newValue in
                            if newValue {
                                selectedFilters.insert(filter.id)
                            } else {
                                selectedFilters.remove(filter.id)
                            }
                        }
                    ))
                }
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Button("Update Selected") {
                    Task {
                        let filtersToUpdate = filterListManager.availableUpdates.filter { selectedFilters.contains($0.id) }
                        await filterListManager.updateSelectedFilters(filtersToUpdate)
                        isPresented = false
                    }
                }
                .disabled(selectedFilters.isEmpty)
            }
            .padding()
        }
        .frame(width: 300, height: 400)
    }
}
