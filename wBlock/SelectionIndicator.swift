import SwiftUI

/// One choice in a pick list, drawn with the native control as in the
/// available-updates review (#1088): a checkbox on macOS, a switch on iOS.
/// Onboarding, Annoyances Info, and the review share it.
struct SelectableRow: View {
    let title: Text
    /// A short line under the title, such as the languages a list covers.
    var caption: String = ""
    var subtitle: String = ""
    var badge: Text? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { _ in action() })) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    title
                        .fontWeight(.medium)
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
                if !caption.isEmpty {
                    Text(caption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        #if os(macOS)
        .toggleStyle(RowCheckboxStyle())
        #endif
    }
}

/// Rows in one grouped box, divided like a Form section, for pick lists
/// that sit in a scroll view rather than a Form.
struct SelectableRowGroup<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder let row: (Data.Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                row(element)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                if index < data.count - 1 {
                    Divider().padding(.leading, 12)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#if os(macOS)
/// A checkbox centered on its label, toggled by a click anywhere on the row (#1034).
struct RowCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.checkbox)
                .labelsHidden()
            configuration.label.accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
    }
}
#endif
