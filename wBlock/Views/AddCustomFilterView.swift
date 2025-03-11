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
    @State private var filterDescription: String = "" // Optional description

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Custom Filter")
                .font(.largeTitle)
                .fontWeight(.bold)

            TextField("Filter Name", text: $filterName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            TextField("Filter URL", text: $filterURLString)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            TextField("Description (Optional)", text: $filterDescription)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            Spacer()

            HStack(spacing: 20) {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
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
                    if let url = URL(string: filterURLString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        // Create a new FilterList object
                        let newFilter = FilterList(
                            id: UUID(),
                            name: filterName.trimmingCharacters(in: .whitespacesAndNewlines),
                            url: url,
                            category: .custom, isSelected: true, description: filterDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                            version: ""
                        )

                        // Add it using our new method
                        filterListManager.addCustomFilterList(newFilter)
                        presentationMode.wrappedValue.dismiss()
                    } else {
                        // Optionally, present an alert for invalid URL
                    }
                }) {
                    Text("Add")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(filterName.isEmpty || filterURLString.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 450, height: 350)
        .background(Color(.windowBackgroundColor))
    }
}
