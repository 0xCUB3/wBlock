import SwiftUI

struct UnifiedTabCardSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 1)

            VStack(spacing: 0) {
                content
            }
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
    }
}

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
