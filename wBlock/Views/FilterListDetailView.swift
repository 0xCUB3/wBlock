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
        VStack(alignment: .leading, spacing: 20) {
            Text(filterList.name)
                .font(.title)
            Text("Category: \(filterList.category.rawValue)")
            VStack(alignment: .leading, spacing: 5) {
                Text("URL:")
                Link(filterList.url.absoluteString, destination: filterList.url)
                    .foregroundColor(.blue)
            }
            Text("Status: \(filterList.isSelected ? "Enabled" : "Disabled")")
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}

class WindowDelegate: NSObject, NSWindowDelegate, ObservableObject {
    @Published var shouldShowExitAlert = false
    var hasUnappliedChanges: () -> Bool = { false }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if hasUnappliedChanges() {
            shouldShowExitAlert = true
            return false
        }
        NSApplication.shared.terminate(nil)
        return true
    }
}
