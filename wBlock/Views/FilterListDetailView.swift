//
//  FilterListDetailView.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//

import SwiftUI
import SwiftData

struct FilterListDetailView: View {
    let filterList: FilterList

    var body: some View {
        List { // Use List for a standard iOS layout
            Section(header: Text("Name").textCase(.none)) {
                Text(filterList.name)
            }
            Section(header: Text("Category").textCase(.none)) {
                Text(filterList.category.rawValue)
            }
            Section(header: Text("URL").textCase(.none)) {
                Link(filterList.url.absoluteString, destination: filterList.url)
            }
            Section(header: Text("Status").textCase(.none)) {
                Text(filterList.isSelected ? "Enabled" : "Disabled")
            }
        }
        .listStyle(.insetGrouped) // Use insetGrouped for iOS style
        .navigationTitle(filterList.name) // Set navigation title
        .navigationBarTitleDisplayMode(.inline)
    }
}
