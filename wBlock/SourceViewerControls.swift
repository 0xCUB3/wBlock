import SwiftUI

struct SourceViewerControls: View {
    @Binding var wrapsLines: Bool
    let onSearch: () -> Void

    private var controlSize: CGFloat {
        #if os(iOS)
        44
        #else
        24
        #endif
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .frame(width: controlSize, height: controlSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .noFocusRingCompat()
            .accessibilityLabel("Search")
            Button { wrapsLines.toggle() } label: {
                Image(systemName: wrapsLines ? "text.justify.left" : "text.alignleft")
                    .frame(width: controlSize, height: controlSize)
                    .contentShape(Rectangle())
                    .foregroundStyle(wrapsLines ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .noFocusRingCompat()
            .accessibilityLabel("Wrap Lines")
            .accessibilityValue(wrapsLines ? String(localized: "On") : String(localized: "Off"))
        }
    }
}
