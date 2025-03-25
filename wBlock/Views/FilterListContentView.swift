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
    @Binding var showOnlyEnabledFilters: Bool // Add the binding
    
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
        switch (selectedCategory) {
        case .all:
            ForEach(cachedCategories, id: \.self) { category in
                let filteredLists = showOnlyEnabledFilters
                ? filterListManager.filterLists(for: category).filter { $0.isSelected }
                : filterListManager.filterLists(for: category)
                
                if !filteredLists.isEmpty {
                    categorySection(for: category, filters: filteredLists)
                }
            }
        case .custom:
            let filteredCustomLists = showOnlyEnabledFilters
            ? filterListManager.customFilterLists.filter { $0.isSelected }
            : filterListManager.customFilterLists;
            
            ForEach(filteredCustomLists) { filter in
                FilterRowView(filter: filter, filterListManager: filterListManager)
                    .padding(.horizontal)
                if filter.id != filteredCustomLists.last?.id {
                    Divider()
                        .padding(.leading)
                }
            }
        default:
            let filteredLists = showOnlyEnabledFilters
            ? filterListManager.filterLists(for: selectedCategory).filter { $0.isSelected }
            : filterListManager.filterLists(for: selectedCategory)
            ForEach(filteredLists) { filter in
                
                FilterRowView(filter: filter, filterListManager: filterListManager)
                    .padding(.horizontal)
                
                if filter.id != filteredLists.last?.id {
                    Divider()
                        .padding(.leading)
                }
            }
        }
    }
    
    @ViewBuilder
    private func categorySection(for category: FilterListCategory, filters: [FilterList]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(category.rawValue)
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 8)
            
            ForEach(filters) { filter in
                FilterRowView(filter: filter, filterListManager: filterListManager)
                    .padding(.horizontal)
                if filter.id != filters.last?.id {
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
