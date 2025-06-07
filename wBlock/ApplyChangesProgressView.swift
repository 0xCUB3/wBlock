//
//  ApplyChangesProgressView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI
import wBlockCoreService

struct ApplyChangesProgressView: View {
    @ObservedObject var filterManager: AppFilterManager
    @Binding var isPresented: Bool
    
    private var selectedFilters: [FilterList] {
        filterManager.filterLists.filter { $0.isSelected }
    }
    
    private var progressPercentage: Int {
        let clampedProgress = max(0.0, min(1.0, filterManager.progress))
        return Int(clampedProgress * 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed Header - only show when we have content to show
            if filterManager.isLoading || (filterManager.progress >= 1.0 && hasStatistics) {
                VStack(spacing: 16) {
                    ZStack {
                        // Centered title
                        Text(titleText)
                            .font(.title3)
                            .fontWeight(.medium)
                        // Close button aligned to trailing edge (only show when complete)
                        HStack {
                            Spacer()
                            if !filterManager.isLoading && filterManager.progress >= 1.0 {
                                Button {
                                    isPresented = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Close")
                            }
                        }
                    }
                    // Only show phase description if not redundant
                    if filterManager.isLoading && !filterManager.conversionStageDescription.isEmpty && filterManager.conversionStageDescription != titleText {
                        Text(filterManager.conversionStageDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(minHeight: 20) // Fixed height to prevent jumping
                    }
                    // Progress bar (only during conversion)
                    if filterManager.isLoading {
                        VStack(spacing: 8) {
                            ProgressView(value: filterManager.progress)
                                .progressViewStyle(.linear)
                                .scaleEffect(y: 1.2)
                            Text("\(progressPercentage)%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .monospacedDigit() // Ensures consistent width for numbers
                        }
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            
            // Content Area
            if filterManager.isLoading {
                // Show phase indicators during conversion
                ScrollView {
                    VStack(spacing: 16) {
                        phaseIndicatorsView
                    }
                    .padding(20)
                }
            } else if filterManager.progress >= 1.0 && hasStatistics {
                // Show statistics when complete
                ScrollView {
                    VStack {
                        statisticsView
                            .padding(20)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: filterManager.isLoading)
        .animation(.easeInOut(duration: 0.3), value: filterManager.progress)
        #if os(macOS)
        .frame(
            minWidth: 420, idealWidth: 450, maxWidth: 480,
            minHeight: 350, idealHeight: 400, maxHeight: 500
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        #else
        .frame(
            minWidth: 0, idealWidth: .infinity, maxWidth: .infinity,
            minHeight: 0, idealHeight: .infinity, maxHeight: .infinity
        )
        #endif
        // Set initial view state before starting the conversion process
        .task {
            if filterManager.isLoading {
                // Give the UI a chance to render before starting heavy operations
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
            }
        }
    }
    
    private var titleText: String {
        // Only show "Applied" if we've actually completed a conversion
        if filterManager.progress >= 1.0 && !filterManager.isLoading {
            return "Filter Lists Applied"
        } else {
            return "Converting Filter Lists"
        }
    }
    
    private var hasStatistics: Bool {
        // Only show statistics if we have meaningful data
        return filterManager.lastRuleCount > 0 || !filterManager.ruleCountsByCategory.isEmpty
    }
    
    @ViewBuilder
    private var phaseIndicatorsView: some View {
        VStack(spacing: 0) {
            ForEach(phaseData, id: \.title) { phase in
                phaseRow(
                    icon: phase.icon,
                    title: phase.title,
                    detail: phase.detail,
                    isActive: phase.isActive,
                    isCompleted: phase.isCompleted
                )
                
                if phase.title != phaseData.last?.title {
                    Divider()
                        .padding(.leading, 32)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
    
    private var phaseData: [(icon: String, title: String, detail: String?, isActive: Bool, isCompleted: Bool)] {
        [
            (
                icon: "folder.badge.questionmark",
                title: "Reading Files",
                detail: filterManager.totalFiltersCount > 0 ? "\(filterManager.processedFiltersCount)/\(filterManager.totalFiltersCount) extensions" : nil,
                isActive: filterManager.processedFiltersCount < filterManager.totalFiltersCount && !filterManager.isInConversionPhase,
                isCompleted: filterManager.processedFiltersCount >= filterManager.totalFiltersCount || filterManager.progress > 0.6
            ),
            (
                icon: "gearshape.2",
                title: "Converting Rules",
                detail: filterManager.currentFilterName.isEmpty ? nil : "Processing \(filterManager.currentFilterName)",
                isActive: filterManager.isInConversionPhase,
                isCompleted: filterManager.progress > 0.75
            ),
            (
                icon: "square.and.arrow.down",
                title: "Saving & Building",
                detail: (filterManager.isInSavingPhase || filterManager.isInEnginePhase || (filterManager.progress > 0.7 && filterManager.progress < 0.95)) ? "Writing files and building engines" : nil,
                isActive: filterManager.isInSavingPhase || filterManager.isInEnginePhase || (filterManager.progress > 0.7 && filterManager.progress < 0.95),
                isCompleted: filterManager.progress > 0.9
            ),
            (
                icon: "arrow.clockwise",
                title: "Reloading Extensions",
                detail: filterManager.isInReloadPhase && !filterManager.currentFilterName.isEmpty ? "Reloading \(filterManager.currentFilterName)" : nil,
                isActive: filterManager.isInReloadPhase,
                isCompleted: filterManager.progress >= 1.0
            )
        ]
    }
    
    private func phaseRow(icon: String, title: String, detail: String?, isActive: Bool, isCompleted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isCompleted ? .green : (isActive ? .blue : .secondary))
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isActive ? .medium : .regular)
                    .foregroundColor(isCompleted ? .green : (isActive ? .primary : .secondary))
                
                // Reserve space for detail text to prevent layout jumping
                Group {
                    if let detail = detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(" ") // Invisible placeholder to maintain height
                            .font(.caption)
                            .opacity(0)
                    }
                }
                .frame(minHeight: 16, alignment: .leading) // Fixed height and alignment
            }
            
            Spacer()
            
            Group {
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.subheadline)
                } else if isActive {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 16, height: 16)
                } else {
                    // Keep consistent spacing even when no icon
                    Spacer()
                        .frame(width: 16, height: 16)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private var statisticsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Overall statistics
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .foregroundColor(.blue)
                    Text("Overall Statistics")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    let statisticsData = buildOverallStatisticsData()
                    ForEach(Array(statisticsData.enumerated()), id: \.offset) { index, stat in
                        statisticCard(
                            title: stat.title,
                            value: stat.value,
                            icon: stat.icon,
                            color: stat.color
                        )
                    }
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            
            // Per-category statistics (if available)
            if !filterManager.ruleCountsByCategory.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                            .foregroundColor(.orange)
                        Text("Category Statistics")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        let categoryStatistics = buildCategoryStatisticsData()
                        ForEach(Array(categoryStatistics.enumerated()), id: \.offset) { index, stat in
                            statisticCard(
                                title: stat.title,
                                value: stat.value,
                                icon: stat.icon,
                                color: stat.color,
                                showWarning: stat.showWarning
                            )
                        }
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    private func buildOverallStatisticsData() -> [(title: String, value: String, icon: String, color: Color)] {
        var stats: [(title: String, value: String, icon: String, color: Color)] = []
        
        if filterManager.sourceRulesCount > 0 {
            stats.append((
                title: "Source Rules",
                value: filterManager.sourceRulesCount.formatted(),
                icon: "doc.text",
                color: .orange
            ))
        }
        
        if filterManager.lastRuleCount > 0 {
            stats.append((
                title: "Safari Rules",
                value: filterManager.lastRuleCount.formatted(),
                icon: "shield.lefthalf.filled",
                color: .blue
            ))
        }
        
        if filterManager.lastConversionTime != "N/A" {
            stats.append((
                title: "Conversion",
                value: filterManager.lastConversionTime,
                icon: "clock",
                color: .green
            ))
        }
        
        if filterManager.lastReloadTime != "N/A" {
            stats.append((
                title: "Reload",
                value: filterManager.lastReloadTime,
                icon: "arrow.clockwise",
                color: .purple
            ))
        }
        
        return stats
    }
    
    private func buildCategoryStatisticsData() -> [(title: String, value: String, icon: String, color: Color, showWarning: Bool)] {
        var stats: [(title: String, value: String, icon: String, color: Color, showWarning: Bool)] = []
        
        // Sort categories alphabetically for consistent display
        let sortedCategories = filterManager.ruleCountsByCategory.keys.sorted { $0.rawValue < $1.rawValue }
        
        for category in sortedCategories {
            // Skip "all" category as it's not a real content blocker category
            if category == .all { continue }
            
            if let ruleCount = filterManager.ruleCountsByCategory[category] {
                let showWarning = filterManager.categoriesApproachingLimit.contains(category)
                stats.append((
                    title: category.rawValue,
                    value: ruleCount.formatted(),
                    icon: categoryIcon(for: category),
                    color: categoryColor(for: category),
                    showWarning: showWarning
                ))
            }
        }
        
        return stats
    }
    
    private func categoryIcon(for category: FilterListCategory) -> String {
        switch category {
        case .ads:
            return "rectangle.slash"
        case .privacy:
            return "eye.slash"
        case .security:
            return "shield"
        case .multipurpose:
            return "square.grid.2x2"
        case .annoyances:
            return "hand.raised"
        case .experimental:
            return "flask"
        case .foreign:
            return "globe"
        case .custom:
            return "gearshape"
        default:
            return "list.bullet"
        }
    }
    
    private func categoryColor(for category: FilterListCategory) -> Color {
        switch category {
        case .ads:
            return .red
        case .privacy:
            return .blue
        case .security:
            return .green
        case .multipurpose:
            return .orange
        case .annoyances:
            return .purple
        case .experimental:
            return .yellow
        case .foreign:
            return .mint
        case .custom:
            return .gray
        default:
            return .primary
        }
    }
    
    private func statisticCard(title: String, value: String, icon: String, color: Color, showWarning: Bool = false) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                if showWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 10))
                        .offset(x: 12, y: -8)
                }
            }
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
