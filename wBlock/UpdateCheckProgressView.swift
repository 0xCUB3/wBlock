import SwiftUI

struct UpdateCheckProgressView: View {
    @ObservedObject var filterManager: AppFilterManager
    /// Stays set while the card fades out, so the finished check's progress
    /// text doesn't show through on the way out (#1023).
    @State private var showsNoUpdates = false

    private var counter: String? {
        guard let progress = filterManager.updateCheckProgress, progress.total > 0 else { return nil }
        return "\(progress.completed.formatted()) / \(progress.total.formatted())"
    }

    @ViewBuilder private var content: some View {
        Group {
            if showsNoUpdates {
                noUpdates
            } else {
                progress
            }
        }
        .padding(24)
        .frame(idealWidth: 380, maxWidth: 440)
    }

    private var noUpdates: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("No Updates Found")
                    .font(.headline)
                Text("You're already using the latest filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Button("OK") { filterManager.showingNoUpdatesAlert = false }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.defaultAction)
                Button("Apply Anyway") {
                    filterManager.showingNoUpdatesAlert = false
                    filterManager.forceApplyChanges()
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
            .fixedSize()
        }
        .task {
            // Dismisses itself; tapping outside closes it sooner.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            filterManager.showingNoUpdatesAlert = false
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(filterManager.statusDescription)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if let counter {
                    Spacer()
                    Text(verbatim: counter)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: filterManager.updateCheckProgress.map { Double($0.fraction) })
                .progressViewStyle(.linear)
        }
    }

    var body: some View {
        content
            .onAppear { showsNoUpdates = filterManager.showingNoUpdatesAlert }
            .onChangeCompat(of: filterManager.showingNoUpdatesAlert) { _, showing in
                if showing { showsNoUpdates = true }
            }
            .onChangeCompat(of: filterManager.isLoading) { _, loading in
                if loading { showsNoUpdates = false }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            .padding(24)
    }
}
