import SwiftUI

struct UpdateCheckProgressView: View {
    @ObservedObject var filterManager: AppFilterManager

    private var counter: String? {
        guard let progress = filterManager.updateCheckProgress, progress.total > 0 else { return nil }
        return "\(progress.completed.formatted()) / \(progress.total.formatted())"
    }

    private var content: some View {
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
        .padding(24)
        .frame(idealWidth: 380, maxWidth: 440)
    }

    var body: some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
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
