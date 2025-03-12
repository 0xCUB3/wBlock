//
//  AddCustomFilterView.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//

import SwiftUI
import SwiftData

struct AddCustomFilterView: View {
    @ObservedObject var filterListManager: FilterListManager
    @Environment(\.presentationMode) var presentationMode

    @State private var filterName: String = ""
    @State private var filterURLString: String = ""
    @State private var filterDescription: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Filter Name", text: $filterName)
                    TextField("Filter URL", text: $filterURLString)
                        .keyboardType(.URL) // Set keyboard type
                        .textContentType(.URL) // Set text content type
                        .autocapitalization(.none) // Disable autocapitalization
                        .disableAutocorrection(true) // Disable autocorrection
                    TextField("Description (Optional)", text: $filterDescription)
                }

                Section {
                    Button(action: {
                        if let url = URL(string: filterURLString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            // Create a new FilterList object
                            let newFilter = FilterList(
                                id: UUID(),
                                name: filterName.trimmingCharacters(in: .whitespacesAndNewlines),
                                url: url,
                                category: .custom, isSelected: true,
                                description: filterDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                                version: ""
                            )

                            // Add it using our new method
                            filterListManager.addCustomFilterList(newFilter)
                            presentationMode.wrappedValue.dismiss()
                        } else {
                            // Optionally, present an alert for invalid URL
                            // This is a good place for an iOS-specific alert
                        }
                    }) {
                        Text("Add")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(filterName.isEmpty || filterURLString.isEmpty)
                }
            }
            .navigationTitle("Add Custom Filter")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
