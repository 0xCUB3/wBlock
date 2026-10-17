import SwiftUI

extension View {
    @ViewBuilder
    func unifiedTabListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
            .modifier(TabListBottomMargin())
        #else
        // .inset renders rounded card sections like System Settings on macOS.
        listStyle(.inset)
        #endif
    }

    func unifiedTabCardSectionRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .hiddenListRowSeparatorCompat()
            .listRowBackground(Color.clear)
    }
}

#if os(iOS)
/// The last card ends the same 16 points above the tab bar as the side
/// margins and the Mac lists, instead of the list's taller default (#999).
private struct TabListBottomMargin: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.contentMargins(.bottom, 16, for: .scrollContent)
        } else {
            content
        }
    }
}
#endif
