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
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
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
            .frame(height: filterListManager.isUpdating ? 125 : 200)
            .background(Color(.windowBackgroundColor))
            .cornerRadius(8)

            if filterListManager.isUpdating {
                VStack(spacing: 8) {
                    ProgressView(value: filterListManager.progress, total: 1.0) {
                        Text("Downloading missing filters…")
                    }
                    .padding(.horizontal)
                    
                    Text("\(Int(filterListManager.progress * 100))% complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button(action: {
                Task {
                    await filterListManager.updateMissingFilters()
                    presentationMode.wrappedValue.dismiss()
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
            .buttonStyle(PlainButtonStyle())
            .disabled(filterListManager.isUpdating)
        }
        .padding()
        .frame(width: 400, height: 400)
        .background(Color(.windowBackgroundColor))
    }
}
