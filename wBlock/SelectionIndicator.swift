import SwiftUI

/// A shape-rendered selection mark that avoids SF Symbol circle-outline artifacts.
struct SelectionIndicator: View {
    let isSelected: Bool
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.clear)
            Circle()
                .strokeBorder(
                    Color.secondary.opacity(isSelected ? 0 : 0.7),
                    lineWidth: 1.5
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityHidden(true)
    }
}
