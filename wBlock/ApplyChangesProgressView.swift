//
//  ApplyChangesProgressView.swift
//  wBlock
//
//  Created by Alexander Skula on 10/09/25.
//

import SwiftUI
import wBlockCoreService

struct ApplyChangesProgressView: View {
    @ObservedObject var viewModel: ApplyChangesViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header section
            if viewModel.state.isLoading || viewModel.state.isComplete {
                headerView
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            // Content section
            if viewModel.state.isLoading {
                progressContent
            } else if viewModel.state.isComplete {
                statisticsContent
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.state.isLoading)
        #if os(macOS)
        .frame(
            minWidth: 420, idealWidth: 450, maxWidth: 480,
            minHeight: 350, idealHeight: 400, maxHeight: 500
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 16) {
            ZStack {
                Text(titleText)
                    .font(.title3)
                    .fontWeight(.medium)

                HStack {
                    Spacer()
                    if viewModel.state.isComplete {
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

            if viewModel.state.isLoading && !viewModel.state.stageDescription.isEmpty {
                Text(viewModel.state.stageDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if viewModel.state.isLoading {
                VStack(spacing: 8) {
                    ProgressView(value: viewModel.state.progress)
                        .progressViewStyle(.linear)
                        .scaleEffect(y: 1.2)

                    Text("\(viewModel.state.progressPercentage)%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var titleText: String {
        viewModel.state.isComplete ? "Filter Lists Applied" : "Converting Filter Lists"
    }

    // MARK: - Progress Content

    private var progressContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                phaseIndicatorsView
            }
            .padding(20)
        }
    }

    private var phaseIndicatorsView: some View {
        VStack(spacing: 0) {
            PhaseRow(
                icon: "folder.badge.questionmark",
                title: "Reading Files",
                detail: phaseReadingDetail,
                isActive: !viewModel.state.isReadingComplete,
                isCompleted: viewModel.state.isReadingComplete
            )

            Divider().padding(.leading, 32)

            PhaseRow(
                icon: "gearshape.2",
                title: "Converting Rules",
                detail: phaseConvertingDetail,
                isActive: viewModel.state.isReadingComplete && !viewModel.state.isConvertingComplete,
                isCompleted: viewModel.state.isConvertingComplete
            )

            Divider().padding(.leading, 32)

            PhaseRow(
                icon: "square.and.arrow.down",
                title: "Saving & Building",
                detail: phaseSavingDetail,
                isActive: viewModel.state.isConvertingComplete && !viewModel.state.isSavingComplete,
                isCompleted: viewModel.state.isSavingComplete
            )

            Divider().padding(.leading, 32)

            PhaseRow(
                icon: "arrow.clockwise",
                title: "Reloading Extensions",
                detail: phaseReloadingDetail,
                isActive: viewModel.state.isSavingComplete && !viewModel.state.isReloadingComplete,
                isCompleted: viewModel.state.isReloadingComplete
            )
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // Phase detail helpers (memoized via computed properties)
    private var phaseReadingDetail: String? {
        guard viewModel.state.totalCount > 0 else { return nil }
        return "\(viewModel.state.processedCount)/\(viewModel.state.totalCount) extensions"
    }

    private var phaseConvertingDetail: String? {
        guard !viewModel.state.currentFilterName.isEmpty else { return nil }
        return "Processing \(viewModel.state.currentFilterName)"
    }

    private var phaseSavingDetail: String? {
        guard viewModel.state.isConvertingComplete && !viewModel.state.isSavingComplete else { return nil }
        return "Writing files and building engines"
    }

    private var phaseReloadingDetail: String? {
        guard viewModel.state.isSavingComplete && !viewModel.state.isReloadingComplete,
              !viewModel.state.currentFilterName.isEmpty else { return nil }
        return "Reloading \(viewModel.state.currentFilterName)"
    }

    // MARK: - Statistics Content

    private var statisticsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                overallStatisticsSection

                if !viewModel.state.ruleCountsByCategory.isEmpty {
                    categoryStatisticsSection
                }
            }
            .padding(20)
        }
    }

    private var overallStatisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundColor(.blue)
                Text("Overall Statistics")
                    .font(.headline)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if viewModel.state.sourceRulesCount > 0 {
                    ProgressStatCard(title: "Source Rules", value: viewModel.state.sourceRulesCount.formatted(), icon: "doc.text", color: .orange)
                }
                if viewModel.state.safariRulesCount > 0 {
                    ProgressStatCard(title: "Safari Rules", value: viewModel.state.safariRulesCount.formatted(), icon: "shield.lefthalf.filled", color: .blue)
                }
                if viewModel.state.conversionTime != "N/A" {
                    ProgressStatCard(title: "Conversion", value: viewModel.state.conversionTime, icon: "clock", color: .green)
                }
                if viewModel.state.reloadTime != "N/A" {
                    ProgressStatCard(title: "Reload", value: viewModel.state.reloadTime, icon: "arrow.clockwise", color: .purple)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var categoryStatisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.grid.2x2")
                    .foregroundColor(.orange)
                Text("Category Statistics")
                    .font(.headline)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(sortedCategories, id: \.rawValue) { category in
                    if let count = viewModel.state.ruleCountsByCategory[category], category != .all {
                        ProgressStatCard(
                            title: category.rawValue,
                            value: count.formatted(),
                            icon: categoryIcon(for: category),
                            color: categoryColor(for: category),
                            showWarning: viewModel.state.categoriesApproachingLimit.contains(category)
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var sortedCategories: [FilterListCategory] {
        viewModel.state.ruleCountsByCategory.keys.sorted { $0.rawValue < $1.rawValue }
    }

    // MARK: - Helpers

    private func categoryIcon(for category: FilterListCategory) -> String {
        switch category {
        case .ads: return "rectangle.slash"
        case .privacy: return "eye.slash"
        case .security: return "shield"
        case .multipurpose: return "square.grid.2x2"
        case .annoyances: return "hand.raised"
        case .experimental: return "flask"
        case .foreign: return "globe"
        case .custom: return "gearshape"
        default: return "list.bullet"
        }
    }

    private func categoryColor(for category: FilterListCategory) -> Color {
        switch category {
        case .ads: return .red
        case .privacy: return .blue
        case .security: return .green
        case .multipurpose: return .orange
        case .annoyances: return .purple
        case .experimental: return .yellow
        case .foreign: return .mint
        case .custom: return .gray
        default: return .primary
        }
    }
}

// MARK: - Subviews

struct PhaseRow: View {
    let icon: String
    let title: String
    let detail: String?
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(isCompleted ? .green : (isActive ? .blue : .secondary))
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isActive ? .medium : .regular)
                    .foregroundColor(isCompleted ? .green : (isActive ? .primary : .secondary))

                Group {
                    if let detail = detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(" ")
                            .font(.caption)
                            .opacity(0)
                    }
                }
                .frame(minHeight: 16, alignment: .leading)
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
                    Spacer()
                        .frame(width: 16, height: 16)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct ProgressStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var showWarning: Bool = false

    var body: some View {
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
