import SwiftUI

#if os(iOS)
/// The disclosure glyph every Settings row uses. Tapping a filter or script
/// row opens its Info sheet, which lists all of the row's actions, and this
/// is what tells the user the row opens at all. The switch stays flush
/// right; the chevron sits between the text and the controls.
struct RowDisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}
#endif
