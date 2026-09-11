import SwiftUI

struct SourceViewerControls: View {
    @Binding var wrapsLines: Bool
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .noFocusRingCompat()
            .accessibilityLabel("Search")
            Button { wrapsLines.toggle() } label: {
                Image(systemName: wrapsLines ? "text.justify.left" : "text.alignleft")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(wrapsLines ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .noFocusRingCompat()
            .accessibilityLabel("Wrap Lines")
            .accessibilityValue(wrapsLines ? String(localized: "On") : String(localized: "Off"))
        }
    }
}
