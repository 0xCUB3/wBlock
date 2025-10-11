//
//  ApplyChangesProgressView.swift
//  wBlock
//
//  Created by Alexander Skula on 10/09/25.
//

import SwiftUI
// The production target exposes FilterListCategory via wBlockCoreService.
#if canImport(wBlockCoreService)
import wBlockCoreService
#endif

struct ApplyChangesProgressView: View {
    @ObservedObject var viewModel: ApplyChangesViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, viewModel.state.isLoading ? 16 : 12)

            if viewModel.state.isLoading {
                progressSection
            } else if let summary = viewModel.state.summary {
                summarySection(summary)
            } else {
                placeholderSection
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.state.isLoading)
        .animation(.easeInOut(duration: 0.2), value: viewModel.state.isComplete)
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 500, minHeight: 360, idealHeight: 400, maxHeight: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        #endif
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.state.isComplete ? "Filters Applied" : "Applying Filter Lists")
                        .font(.title3)
                        .fontWeight(.semibold)

                    if viewModel.state.isLoading && !viewModel.state.statusMessage.isEmpty {
                        Text(viewModel.state.statusMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()

                if viewModel.state.isComplete {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
            }

            if viewModel.state.isLoading {
                VStack(spacing: 6) {
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)

                    HStack(spacing: 8) {
                        Text(progressPercentageText)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: Progress

    private var progressSection: some View {
        ScrollView {
            VStack(spacing: 16) {
                phaseList
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var phaseList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.state.phases.enumerated()), id: \.element.phase) { index, item in
                PhaseRow(step: item, detail: detail(for: item))

                if index < viewModel.state.phases.count - 1 {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func detail(for step: ApplyChangesPhaseProgress) -> String? {
        switch step.phase {
        case .reading:
            guard viewModel.state.totalCount > 0 else { return nil }
            return "Preparing \(viewModel.state.totalCount) extension\(viewModel.state.totalCount == 1 ? "" : "s")"
        case .converting:
            guard !viewModel.state.currentFilterName.isEmpty else { return nil }
            return "Processing \(viewModel.state.currentFilterName)"
        case .saving:
            return step.status == .complete ? "Saved" : "Writing files and building engines"
        case .reloading:
            guard !viewModel.state.currentFilterName.isEmpty else { return nil }
            return step.status == .complete ? "Reloaded" : "Reloading \(viewModel.state.currentFilterName)"
        }
    }

    // MARK: Summary

    private func summarySection(_ summary: ApplyChangesSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                cardSection(title: "Overall Statistics", icon: "chart.bar.doc.horizontal") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        if summary.sourceRules > 0 {
                            ProgressStatCard(title: "Source Rules", value: summary.sourceRules.formatted(), icon: "doc.text", color: .orange)
                        }
                        if summary.safariRules > 0 {
                            ProgressStatCard(title: "Safari Rules", value: summary.safariRules.formatted(), icon: "shield.lefthalf.filled", color: .blue)
                        }
                        if summary.conversionTime != "N/A" {
                            ProgressStatCard(title: "Conversion", value: summary.conversionTime, icon: "clock", color: .green)
                        }
                        if summary.reloadTime != "N/A" {
                            ProgressStatCard(title: "Reload", value: summary.reloadTime, icon: "arrow.clockwise", color: .purple)
                        }
                    }
                }

            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func cardSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var placeholderSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "hourglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Preparing…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

// MARK: - Subviews

struct PhaseRow: View {
    let step: ApplyChangesPhaseProgress
    let detail: String?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: step.phase.systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.phase.title)
                    .font(.subheadline)
                    .fontWeight(textWeight)
                    .foregroundStyle(titleColor)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusIndicator
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var iconColor: Color {
        switch step.status {
        case .pending: return .secondary
        case .active: return .accentColor
        case .complete: return .green
        }
    }

    private var titleColor: Color {
        switch step.status {
        case .pending: return .secondary
        case .active: return .primary
        case .complete: return .green
        }
    }

    private var textWeight: Font.Weight {
        step.status == .active ? .medium : .regular
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch step.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.quaternary)
        case .active:
            ProgressView()
                .progressViewStyle(.circular)
                .frame(width: 18, height: 18)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

// MARK: - Private helpers

private extension ApplyChangesProgressView {
    var progressValue: Double {
        Swift.min(Swift.max(viewModel.state.progress, 0), 1)
    }

    var progressPercentageText: String {
        let percentage = (progressValue * 100).rounded()
        return "\(Int(percentage))%"
    }
}

struct ProgressStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var showWarning: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)

                if showWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                        .offset(x: 6, y: -6)
                }
            }

            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
