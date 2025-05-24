//
//  ApplyChangesProgressView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI

struct ApplyChangesProgressView: View {
    @ObservedObject var filterManager: AppFilterManager
    @Binding var isPresented: Bool
    
    private var selectedFilters: [FilterList] {
        filterManager.filterLists.filter { $0.isSelected }
    }
    
    private var progressPercentage: Int {
        Int(round(filterManager.progress * 100))
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
                            .animation(.easeInOut(duration: 0.4), value: titleText)
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
                                .transition(.scale.combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.3), value: !filterManager.isLoading)
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
                            .id(filterManager.conversionStageDescription) // Force recreation to prevent overlap
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.3), value: filterManager.conversionStageDescription)
                    }
                    // Progress bar (only during conversion)
                    if filterManager.isLoading {
                        VStack(spacing: 8) {
                            ProgressView(value: filterManager.progress)
                                .progressViewStyle(.linear)
                                .scaleEffect(y: 1.2)
                                .animation(.easeInOut(duration: 0.2), value: filterManager.progress)
                            Text("\(progressPercentage)%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .animation(.easeInOut(duration: 0.2), value: progressPercentage)
                        }
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: filterManager.isLoading)
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: filterManager.isLoading || (filterManager.progress >= 1.0 && hasStatistics))
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
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: filterManager.isLoading)
            } else if filterManager.progress >= 1.0 && hasStatistics {
                // Show statistics when complete
                VStack {
                    statisticsView
                        .padding(20)
                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: filterManager.isLoading)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: filterManager.isLoading)
        #if os(macOS)
        .frame(
            minWidth: 420, idealWidth: 450, maxWidth: 480,
            minHeight: 300, idealHeight: 350, maxHeight: 400
        )
        #else
        .frame(
            minWidth: 0, idealWidth: .infinity, maxWidth: .infinity,
            minHeight: 0, idealHeight: .infinity, maxHeight: .infinity
        )
        #endif
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
        filterManager.sourceRulesCount > 0 || filterManager.lastRuleCount > 0 || 
        filterManager.lastConversionTime != "N/A" || filterManager.lastReloadTime != "N/A"
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
                detail: filterManager.totalFiltersCount > 0 ? "\(filterManager.processedFiltersCount)/\(filterManager.totalFiltersCount) files" : nil,
                isActive: filterManager.processedFiltersCount < filterManager.totalFiltersCount && !filterManager.isInConversionPhase,
                isCompleted: filterManager.processedFiltersCount >= filterManager.totalFiltersCount || filterManager.progress > 0.6
            ),
            (
                icon: "gearshape.2",
                title: "Converting Rules",
                detail: nil,
                isActive: filterManager.isInConversionPhase,
                isCompleted: filterManager.progress > 0.75
            ),
            (
                icon: "square.and.arrow.down",
                title: "Saving & Building",
                detail: nil,
                isActive: filterManager.isInSavingPhase || filterManager.isInEnginePhase,
                isCompleted: filterManager.progress > 0.9
            ),
            (
                icon: "arrow.clockwise",
                title: "Reloading Safari",
                detail: nil,
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
                .animation(.easeInOut(duration: 0.3), value: isCompleted)
                .animation(.easeInOut(duration: 0.2), value: isActive)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(isCompleted ? .green : (isActive ? .primary : .secondary))
                    .animation(.easeInOut(duration: 0.3), value: isCompleted)
                    .animation(.easeInOut(duration: 0.2), value: isActive)
                
                if let detail = detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .id(detail) // Force recreation to prevent overlap
                        .animation(.easeInOut(duration: 0.2), value: detail)
                }
            }
            
            Spacer()
            
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.4), value: isCompleted)
            } else if isActive {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 16, height: 16)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: isActive)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    @ViewBuilder
    private var statisticsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundColor(.blue)
                Text("Statistics")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: filterManager.progress)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                let statisticsData = buildStatisticsData()
                ForEach(Array(statisticsData.enumerated()), id: \.offset) { index, stat in
                    statisticCard(
                        title: stat.title,
                        value: stat.value,
                        icon: stat.icon,
                        color: stat.color
                    )
                    .transition(.scale.combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.4).delay(Double(index) * 0.1), value: filterManager.progress)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
    
    private func buildStatisticsData() -> [(title: String, value: String, icon: String, color: Color)] {
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
    
    private func statisticCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            
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
