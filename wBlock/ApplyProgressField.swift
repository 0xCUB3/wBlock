//
//  ApplyProgressField.swift
//  wBlock
//
//  Created by Alexander Skula on 10/09/25.
//

import SwiftUI

/// Floats running work under the toolbar, below `leading` (#1051): an apply,
/// an update check, and what either one found when it is done. The card sits
/// over the list, so the rows stay put as it comes, changes, and goes (#1059).
struct ProgressBanners<Leading: View>: ViewModifier {
    @ObservedObject var filterManager: AppFilterManager
    @ObservedObject var applyProgress: ApplyChangesViewModel
    @ViewBuilder let leading: Leading

    private enum Banner { case apply, check, applied, noUpdates }

    private var banner: Banner? {
        if filterManager.showingApplyProgressSheet {
            // Picking updates and failed or warning results use the sheet.
            return applyProgress.state.mode == .progress ? .apply : nil
        }
        if filterManager.isLoading && !filterManager.suppressBlockingOverlay { return .check }
        // Paused filters load empty blockers; "0 Safari rules" read as a failure,
        // and the pause banner already says what happened.
        if filterManager.showingAppliedBanner && !filterManager.pausedComponents.contains(.filters) { return .applied }
        return filterManager.showingNoUpdatesAlert ? .noUpdates : nil
    }

    private var dismissDoneBanner: (() -> Void)? {
        switch banner {
        case .applied: return { filterManager.showingAppliedBanner = false }
        case .noUpdates: return { filterManager.showingNoUpdatesAlert = false }
        default: return nil
        }
    }

    func body(content: Content) -> some View {
        let dismiss = dismissDoneBanner
        // The card overlays the content under the leading bar, so it never
        // covers the pause banner.
        content
            .simultaneousGesture(
                TapGesture().onEnded { dismiss?() },
                including: dismiss == nil ? .subviews : .all
            )
            .overlay(alignment: .top) {
                ZStack {
                    if let banner {
                        // One card stays through a swap; the old content fades
                        // out before the new one fades in, so they never overlap.
                        ZStack {
                            bannerContent(banner, dismiss: dismiss ?? {})
                                .id(banner)
                                .transition(.asymmetric(
                                    insertion: .opacity.animation(.easeOut(duration: 0.15).delay(0.1)),
                                    removal: .opacity.animation(.easeIn(duration: 0.1))
                                ))
                        }
                        // A status card, not a bar: wide windows don't stretch it edge to edge.
                        .frame(maxWidth: 440)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        #if os(macOS)
                        // The system's control background sets the card apart from the gray rows under it.
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                        #endif
                        .liquidGlassCompat(cornerRadius: 16)
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                        // Keep taps on the card from reaching the content underneath.
                        .onTapGesture {}
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }
            .topBarCompat { leading }
            .animation(.easeInOut(duration: 0.25), value: banner)
    }

    @ViewBuilder
    private func bannerContent(_ banner: Banner, dismiss: @escaping () -> Void) -> some View {
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
                ),
                dismiss: dismiss
            )
        case .noUpdates:
            DoneBanner(
                title: String(localized: "No Updates Found"),
                message: String(localized: "You're already using the latest filters."),
                dismiss: dismiss
            ) {
                Button("Apply Anyway") {
                    dismiss()
                    filterManager.forceApplyChanges()
                }
            }
        }
    }
}

/// A titled bar with a trailing status line, shared by every banner that runs.
private struct BannerProgress: View {
    let title: String
    let value: Double?
    let status: String

    var body: some View {
        // Text that crossfades reads as two lines on top of each other, so a new
        // title or status swaps at once. Only those changes skip the animation:
        // the text still slides in with the card instead of landing ahead of it.
        ProgressView(value: value) {
            Text(title)
                .animation(nil, value: title)
        } currentValueLabel: {
            Text(status)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .animation(nil, value: status)
        }
        .progressViewStyle(.linear)
        // A Mac bar that starts indeterminate keeps sweeping once it gets a value,
        // so it is rebuilt when it switches between the two.
        .id(value == nil)
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
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return
            }
            dismiss()
        }
    }
}

extension DoneBanner where Action == EmptyView {
    init(title: String, message: String, dismiss: @escaping () -> Void) {
        self.init(title: title, message: message, dismiss: dismiss) { EmptyView() }
    }
}
