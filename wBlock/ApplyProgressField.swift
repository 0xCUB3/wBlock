//
//  ApplyProgressField.swift
//  wBlock
//
//  Created by Alexander Skula on 10/09/25.
//

import SwiftUI

struct ApplyProgressField: View {
    let presentation: ApplyProgressPresentation
    /// After a failure the completed and never-started phases add nothing, so
    /// the sheet shows just the phase that failed and its message.
    var showsOnlyFailedPhase = false

    private var visibleNodes: [ApplyProgressPresentation.Node] {
        guard showsOnlyFailedPhase else { return presentation.nodes }
        let failed = presentation.nodes.filter { $0.status == .failed }
        return failed.isEmpty ? presentation.nodes : failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView(value: presentation.progress) {
                Text(presentation.title)
                    .fixedSize(horizontal: false, vertical: true)
            } currentValueLabel: {
                Text(presentation.progressLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
            .tint(presentation.isFailed ? Color.red : Color.accentColor)
            .accessibilityLabel(String(localized: "Apply Changes"))
            .accessibilityValue(presentation.progressLabel)

            VStack(spacing: 0) {
                ForEach(Array(visibleNodes.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Divider()
                    }
                    ApplyProgressRow(node: node)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct ApplyProgressRow: View {
    let node: ApplyProgressPresentation.Node

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusLeading
                .id(node.status)
                .frame(width: 16, height: 16)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(node.phase.title)
                        .font(.body)
                        .foregroundStyle(node.status == .pending ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let accessory = node.accessory, !accessory.isEmpty {
                        Spacer(minLength: 8)
                        Text(accessory)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }

                if let detail = node.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.phase.title)
        .accessibilityValue(node.accessibilityValue)
    }

    @ViewBuilder
    private var statusLeading: some View {
        switch node.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.quaternary)
                .imageScale(.small)
        case .active:
            ProgressView()
                .controlSize(.small)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.small)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .imageScale(.small)
        }
    }
}

/// Puts running work under the toolbar, below `leading` (#1051): an apply,
/// an update check, and what either one found when it is done. The content
/// moves with the banner as it comes, changes, and goes.
struct ProgressBanners<Leading: View>: ViewModifier {
    @ObservedObject var filterManager: AppFilterManager
    @ObservedObject var applyProgress: ApplyChangesViewModel
    @ViewBuilder let leading: Leading
    @State private var showsApplied = false

    private enum Banner { case apply, check, applied, noUpdates }

    private var banner: Banner? {
        if filterManager.showingApplyProgressSheet {
            // Picking updates and failed or warning results use the sheet.
            return applyProgress.state.mode == .progress ? .apply : nil
        }
        if filterManager.isLoading && !filterManager.suppressBlockingOverlay { return .check }
        if showsApplied { return .applied }
        return filterManager.showingNoUpdatesAlert ? .noUpdates : nil
    }

    func body(content: Content) -> some View {
        content
            .topBarCompat {
                VStack(spacing: 0) {
                    leading
                    if let banner {
                        Group {
                            switch banner {
                            case .apply:
                                ApplyProgressBanner(presentation: .make(from: applyProgress.state))
                            case .check:
                                UpdateCheckBanner(filterManager: filterManager)
                            case .applied:
                                DoneBanner(
                                    title: String(localized: "Changes Applied"),
                                    message: String.localizedStringWithFormat(
                                        String(localized: "%@ Safari rules"),
                                        filterManager.lastRuleCount.formatted()
                                    )
                                ) { showsApplied = false }
                            case .noUpdates:
                                DoneBanner(
                                    title: String(localized: "No Updates Found"),
                                    message: String(localized: "You're already using the latest filters.")
                                ) {
                                    filterManager.showingNoUpdatesAlert = false
                                } action: {
                                    Button("Apply Anyway") {
                                        filterManager.showingNoUpdatesAlert = false
                                        filterManager.forceApplyChanges()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: banner)
            // Only a run the user watched ends in this banner; one that needs
            // attention stays in the sheet, and background runs never had it.
            .onChangeCompat(of: filterManager.showingApplyProgressSheet) { _, showing in
                showsApplied = !showing && applyProgress.state.mode == .result
                    && !applyProgress.state.resultNeedsAttention && filterManager.failedReloadTargets.isEmpty
            }
    }
}

/// A titled bar with a trailing status line, shared by every banner that runs.
private struct BannerProgress: View {
    let title: String
    let value: Double?
    let status: String

    var body: some View {
        ProgressView(value: value) {
            Text(title)
        } currentValueLabel: {
            Text(status)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .progressViewStyle(.linear)
        .animation(.easeInOut(duration: 0.25), value: value)
    }
}

/// The current step, what it is working on, and how far along it is.
private struct ApplyProgressBanner: View {
    let presentation: ApplyProgressPresentation

    var body: some View {
        BannerProgress(
            title: presentation.title,
            value: presentation.progress,
            // The first step's status line can just repeat its title.
            status: [presentation.detail, presentation.fractionLabel ?? presentation.progressLabel]
                .compactMap { $0 }
                .filter {
                    $0.trimmingCharacters(in: .punctuationCharacters)
                        .localizedCaseInsensitiveCompare(presentation.title) != .orderedSame
                }
                .joined(separator: " · ")
        )
    }
}

private struct UpdateCheckBanner: View {
    @ObservedObject var filterManager: AppFilterManager

    var body: some View {
        let progress = filterManager.updateCheckProgress.flatMap { $0.total > 0 ? $0 : nil }
        BannerProgress(
            title: filterManager.statusDescription,
            value: progress.map { Double($0.fraction) },
            status: progress.map { "\($0.completed.formatted()) / \($0.total.formatted())" } ?? ""
        )
    }
}

/// Says how a finished apply or check went, and leaves on its own.
private struct DoneBanner<Action: View>: View {
    let title: String
    let message: String
    let dismiss: () -> Void
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            action
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Close")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            dismiss()
        }
    }
}

extension DoneBanner where Action == EmptyView {
    init(title: String, message: String, dismiss: @escaping () -> Void) {
        self.init(title: title, message: message, dismiss: dismiss) { EmptyView() }
    }
}
