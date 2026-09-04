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

/// Shared tappable selection row used by onboarding pick lists and the
/// apply-updates review sheet. Every selection list renders through this row
/// so spacing, typography, and accessibility stay consistent.
struct SelectableRow: View {
    enum Style {
        /// Bare row for use inside a `List` section.
        case listRow
        /// Row inside a shared grouped material container.
        case groupedRow
        /// Standalone material card.
        case card
    }

    let title: Text
    var subtitle: String = ""
    var badge: Text? = nil
    let isSelected: Bool
    var style: Style = .listRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                SelectionIndicator(isSelected: isSelected, size: indicatorSize)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        title
                            .font(titleFont)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        if let badge {
                            badge
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .cornerRadius(4)
                        }
                    }

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(contentPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .modifier(SelectableRowBackground(style: style, isSelected: isSelected))
    }

    private var indicatorSize: CGFloat {
        style == .listRow ? 18 : 20
    }

    private var titleFont: Font {
        style == .listRow ? .body : .headline
    }

    private var contentPadding: EdgeInsets {
        switch style {
        case .listRow:
            return EdgeInsets()
        case .groupedRow:
            return EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        case .card:
            return EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        }
    }
}

private struct SelectableRowBackground: ViewModifier {
    let style: SelectableRow.Style
    let isSelected: Bool

    func body(content: Content) -> some View {
        if style == .card {
            content.liquidGlassCompat(
                cornerRadius: 16,
                material: isSelected ? .thickMaterial : .regularMaterial
            )
        } else {
            content
        }
    }
}

