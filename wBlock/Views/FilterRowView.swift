//
//  FilterRowView.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//

import SwiftUI
import SwiftData

struct FilterRowView: View {
    let filter: FilterList
    @ObservedObject var filterListManager: FilterListManager
    
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { filter.isSelected },
            set: { _ in filterListManager.toggleFilterListSelection(id: filter.id) }
        )
    }
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filter.name)
                if !filter.version.isEmpty {
                    Text("Version: \(filter.version)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if !filter.description.isEmpty {
                    Text(filter.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: toggleBinding)
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .labelsHidden()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            filterListManager.toggleFilterListSelection(id: filter.id)
        }
        .contextMenu {
            if filter.category == .custom {
                Button("Remove Filter") {
                    filterListManager.removeCustomFilterList(filter)
                }
            }
        }
    }
}
