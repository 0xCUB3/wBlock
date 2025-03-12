//
//  FilterListContentView.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//

import SwiftUI
import SwiftData

struct FilterListContentView: View {
    let selectedCategory: FilterListCategory
    @ObservedObject var filterListManager: FilterListManager
    
    private let cachedCategories = FilterListCategory.allCases.filter { $0 != .all }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                FilterStatsBanner(filterListManager: filterListManager)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                
                categoryContent
            }
        }
        .background(Color(uiColor: .secondarySystemBackground)) // Use UIColor
    }
    
    @ViewBuilder
    private var categoryContent: some View {
        switch selectedCategory {
        case .all:
            ForEach(cachedCategories, id: \.self) { category in
                if !filterListManager.filterLists(for: category).isEmpty {
                    Section(header: Text(category.rawValue).textCase(.none)) { // Use Section header
                        ForEach(filterListManager.filterLists(for: category)) { filter in
                            FilterRowView(filter: filter, filterListManager: filterListManager)
//                                .padding(.horizontal) // Not needed within List
                            // No Divider needed in List
                        }
                    }
                }
            }
            
        case .custom:
            ForEach(filterListManager.customFilterLists) { filter in
                FilterRowView(filter: filter, filterListManager: filterListManager)
                // Divider not needed, List provides separators
            }
            
        default:
            ForEach(filterListManager.filterLists(for: selectedCategory)) { filter in
                FilterRowView(filter: filter, filterListManager: filterListManager)
                // Divider not needed
            }
        }
    }
}
