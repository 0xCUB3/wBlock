import SwiftUI

struct UnifiedTabListStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            #if os(iOS)
                .listStyle(.insetGrouped)
            #else
                .listStyle(.inset)
            #endif
    }
}

struct UnifiedTabCardSectionRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
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
