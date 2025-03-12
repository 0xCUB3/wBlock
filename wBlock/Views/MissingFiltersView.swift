//
//  MissingFiltersView.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//
import SwiftUI
import SwiftData

struct MissingFiltersView: View {
    @ObservedObject var filterListManager: FilterListManager
    @Environment(\.dismiss) var dismiss // Use .dismiss

    var body: some View {
        NavigationView { // Use NavigationView
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
                // .frame(height: 200) // Remove fixed height, List will scroll
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(8)

                Button(action: {
                    Task {
                        await filterListManager.updateMissingFilters()
                        dismiss()
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
            }
            .padding()
            #if os(macOS)
            .frame(width: 400, height: 400)
            #endif
            .background(Color(uiColor: .systemBackground))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
