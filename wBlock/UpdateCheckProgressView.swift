import SwiftUI

struct UpdateCheckProgressView: View {
    @ObservedObject var filterManager: AppFilterManager
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    private var counter: String? {
        guard let progress = filterManager.updateCheckProgress, progress.total > 0 else { return nil }
        return "\(progress.completed.formatted()) / \(progress.total.formatted())"
    }

    @ViewBuilder private var content: some View {
        Group {
            #if os(iOS)
            if filterManager.showingNoUpdatesAlert {
                noUpdates
            } else {
                progress
            }
            #else
            progress
            #endif
        }
        .padding(24)
        .frame(idealWidth: 380, maxWidth: 440)
    }

    #if os(iOS)
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
            Button("OK") { filterManager.showingNoUpdatesAlert = false }
                .buttonStyle(.bordered)
        }
        .frame(maxHeight: .infinity)
        .task {
            // Dismisses itself; swiping down or tapping outside closes it sooner.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            filterManager.showingNoUpdatesAlert = false
        }
    }
    #endif

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
        #if os(iOS)
        // iPhone ignores detents in landscape and shows a full-height sheet, which leaves a
        // lone progress bar in a page of white. Float a card over a clear sheet instead.
        if #available(iOS 16.4, *), verticalSizeClass == .compact {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(24)
                .presentationBackground(.clear)
                .presentationDragIndicator(.hidden)
        } else if #available(iOS 16.0, *) {
            content
                .presentationDetents([.height(160)])
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
