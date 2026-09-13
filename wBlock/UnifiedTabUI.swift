import SwiftUI

extension View {
    @ViewBuilder
    func unifiedTabListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
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
