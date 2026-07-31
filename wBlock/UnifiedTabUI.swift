import SwiftUI

struct UnifiedTabListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
            content.listStyle(.insetGrouped)
        #else
            // .inset renders rounded card sections like System Settings on macOS
            content.listStyle(.inset)
        #endif
    }
}

struct UnifiedTabCardSectionRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .hiddenListRowSeparatorCompat()
            .listRowBackground(Color.clear)
    }
}

extension View {
    func unifiedTabListStyle() -> some View {
        modifier(UnifiedTabListStyleModifier())
    }

    func unifiedTabCardSectionRow() -> some View {
        modifier(UnifiedTabCardSectionRowModifier())
    }
}
