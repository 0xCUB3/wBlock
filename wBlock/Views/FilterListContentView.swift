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
        .background(Color(.textBackgroundColor))
    }
    
    @ViewBuilder
    private var categoryContent: some View {
        switch selectedCategory {
        case .all:
            ForEach(cachedCategories, id: \.self) { category in
                if !filterListManager.filterLists(for: category).isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(category.rawValue)
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        
                        ForEach(filterListManager.filterLists(for: category)) { filter in
                            FilterRowView(filter: filter, filterListManager: filterListManager)
                                .padding(.horizontal)
                                //.id(filter.id.uuidString + filter.version + filter.description) // Optional: Force refresh
                            if filter.id != filterListManager.filterLists(for: category).last?.id {
                                Divider()
                                    .padding(.leading)
                            }
                        }
                    }
                    if category != cachedCategories.last {
                        Divider()
                            .padding(.vertical, 8)
                    }
                }
            }
            
        case .custom:
            ForEach(filterListManager.customFilterLists) { filter in
                FilterRowView(filter: filter, filterListManager: filterListManager)
                    .padding(.horizontal)
                
                if filter.id != filterListManager.customFilterLists.last?.id {
                    Divider()
                        .padding(.leading)
                }
            }
            
        default:
            ForEach(filterListManager.filterLists(for: selectedCategory)) { filter in
                FilterRowView(filter: filter, filterListManager: filterListManager)
                    .padding(.horizontal)
                
                if filter.id != filterListManager.filterLists(for: selectedCategory).last?.id {
                    Divider()
                        .padding(.leading)
                }
            }
        }
    }
}
