//
//  ApplyChangesProgressView.swift
//  wBlock
//
//  Created by Alexander Skula on 10/09/25.
//

import SwiftUI

struct ApplyChangesProgressView: View {
    @ObservedObject var viewModel: ApplyChangesViewModel
    @Binding var isPresented: Bool

    var body: some View {
        SheetContainer {
            VStack(spacing: 0) {
                SheetHeader(title: "Apply Changes", isLoading: viewModel.state.isLoading) {
                    isPresented = false
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ZStack(alignment: .topLeading) {
                            if viewModel.state.isLoading {
                                progressCard
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            } else if let summary = viewModel.state.summary {
                                summaryCard(summary)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .animation(.easeInOut(duration: 0.25), value: viewModel.state.isLoading)
                        .animation(.easeInOut(duration: 0.25), value: viewModel.state.isComplete)

                        if viewModel.state.isLoading {
                            phaseCard
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.state.isLoading)
                        }
                    }
                    .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    if viewModel.state.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    Text(headerTitle)
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    title: "Extensions",
                    value: processedText,
                    icon: "puzzlepiece.extension",
                    pillColor: .blue,
                    valueColor: .primary
                )
                StatCard(
                    title: "Updates",
                    value: viewModel.state.updatesFound.formatted(),
                    icon: "arrow.down.circle",
                    pillColor: .green,
                    valueColor: .primary
                )
            }
        }
        .padding(16)
        .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
    }

    private var phaseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(viewModel.state.phases.indices, id: \.self) { index in
                    let step = viewModel.state.phases[index]
                    PhaseRow(
                        step: step,
                        detail: detail(for: step),
                        subProgress: subProgress(for: step.phase, status: step.status)
                    )
                    if index < viewModel.state.phases.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
    }

    private func summaryCard(_ summary: ApplyChangesSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    title: "Safari Rules",
                    value: summary.safariRules.formatted(),
                    icon: "shield.lefthalf.filled",
                    pillColor: .blue,
                    valueColor: .primary
                )
                StatCard(
                    title: "Source Rules",
                    value: summary.sourceRules.formatted(),
                    icon: "doc.text",
                    pillColor: .orange,
                    valueColor: .primary
                )
                StatCard(
                    title: "Conversion",
                    value: summary.conversionTime,
                    icon: "clock",
                    pillColor: .green,
                    valueColor: .primary
                )
                StatCard(
                    title: "Reload",
                    value: summary.reloadTime,
                    icon: "arrow.clockwise",
                    pillColor: .purple,
                    valueColor: .primary
                )
            }

            if !summary.blockersApproachingLimit.isEmpty {
                Text("Near Safari limit: \(summary.blockersApproachingLimit.sorted().joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
    }

    private func detail(for step: ApplyChangesPhaseProgress) -> String? {
        switch step.phase {
        case .updating:
            if step.status == .complete {
                let count = viewModel.state.updatesFound
                if count > 0 {
                    return "Downloaded \(count) update\(count == 1 ? "" : "s")"
                }
                return "No updates available"
            }
            return nil
        case .reading:
            guard viewModel.state.totalCount > 0 else { return nil }
            return "Preparing \(viewModel.state.totalCount) extension\(viewModel.state.totalCount == 1 ? "" : "s")"
        case .converting:
            guard !viewModel.state.currentFilterName.isEmpty else { return nil }
            return viewModel.state.currentFilterName
        case .saving:
            return nil
        case .reloading:
            guard !viewModel.state.currentFilterName.isEmpty else { return nil }
            return viewModel.state.currentFilterName
        }
    }

    private var headerTitle: String {
        if viewModel.state.isComplete {
            return "Applied"
        }
        return "Applying changes…"
    }

    private var headerSubtitle: String {
        if viewModel.state.isComplete {
            return "Filters applied successfully."
        }
        if !viewModel.state.statusMessage.isEmpty {
            return viewModel.state.statusMessage
        }
        return activePhase?.title ?? "Working…"
    }

    private var processedText: String {
        let total = viewModel.state.totalCount
        if total > 0 {
            return "\(total)"
        }
        return "—"
    }

    private var activePhase: ApplyChangesPhase? {
        viewModel.state.phases.first(where: { $0.status == .active })?.phase
    }

    private func subProgress(for phase: ApplyChangesPhase, status: ApplyChangesPhaseStatus) -> PhaseRow.SubProgress? {
        switch phase {
        case .converting:
            guard status == .active else { return nil }

            let totalCount = viewModel.state.totalCount
            let done = viewModel.state.convertingDone
            let total = Double(max(1, totalCount))
            let fraction = Swift.min(Swift.max(Double(done) / total, 0), 1)

            if totalCount > 0, done >= totalCount {
                return nil
            }

            let label = totalCount > 0
                ? "\(done)/\(totalCount) completed"
                : nil

            return PhaseRow.SubProgress(value: fraction, label: label)

        case .reloading:
            guard status == .active else { return nil }

            let totalCount = viewModel.state.totalCount
            let done = viewModel.state.reloadingDone
            let total = Double(max(1, totalCount))
            let fraction = Swift.min(Swift.max(Double(done) / total, 0), 1)

            let label = totalCount > 0
                ? "\(done)/\(totalCount) completed"
                : nil

            if totalCount > 0, done >= totalCount {
                return nil
            }

            return PhaseRow.SubProgress(value: fraction, label: label)

        case .updating, .reading, .saving:
            return nil
        }
    }
}

private struct PhaseRow: View {
    let step: ApplyChangesPhaseProgress
    let detail: String?
    let subProgress: SubProgress?

    struct SubProgress {
        let value: Double
        let label: String?
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                statusLeading
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.phase.title)
                        .font(.subheadline)
                        .fontWeight(step.status == .active ? .semibold : .regular)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            if let subProgress {
                HStack(spacing: 10) {
                    ProgressView(value: subProgress.value)
                        .progressViewStyle(.linear)
                        .scaleEffect(y: 1.15)

                    if let label = subProgress.label {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.leading, 30)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusLeading: some View {
        switch step.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .active:
            ProgressView()
                .controlSize(.small)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
