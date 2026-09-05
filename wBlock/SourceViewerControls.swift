import SwiftUI

struct SourceViewerControls: View {
    @Binding var wrapsLines: Bool
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass").frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .noFocusRingCompat()
            .accessibilityLabel("Search")
            Button { wrapsLines.toggle() } label: {
                Image(systemName: wrapsLines ? "text.justify.left" : "text.alignleft")
                    .frame(width: 28, height: 28)
                    .foregroundStyle(wrapsLines ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .noFocusRingCompat()
            .accessibilityLabel("Wrap Lines")
            .accessibilityValue(wrapsLines ? String(localized: "On") : String(localized: "Off"))
        }
    }
}
