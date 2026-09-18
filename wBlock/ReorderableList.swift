import SwiftUI

struct ReorderableRows<Item: Identifiable, Row: View>: View where Item.ID == UUID {
    let items: [Item]
    let allItems: () -> [Item]
    @Binding var order: Data
    @ViewBuilder let row: (Item) -> Row

    private func move(_ source: IndexSet, to destination: Int) {
        guard source.allSatisfy({ items.indices.contains($0) }),
              (0...items.count).contains(destination) else { return }
        var moved = items
        moved.move(fromOffsets: source, toOffset: destination)
        order = ListDisplayOrder.saving(moved, in: allItems())
    }

    var body: some View {
        ForEach(items) { item in row(item) }
            .onMove(perform: move)
    }
}

struct ContentListSection<Header: View, Content: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section(content: content, header: header)
    }
}

struct ListCategoryHeader: View {
    let title: LocalizedStringKey
    let info: () -> Void
    var anchorID: AnyHashable? = nil
    var isExpanded: Binding<Bool>? = nil

    var body: some View {
        HStack(spacing: 6) {
            // macOS draws the disclosure where the other category titles start,
            // with the title after it; iOS keeps the trailing chevron so every
            // section header keeps the same chrome. The whole header toggles on
            // either platform, which also gives the disclosure a real hit area.
            // The glyph matches AppKit's disclosure triangle in size and sits
            // tight against the title (#823).
            #if os(macOS)
            if let isExpanded {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    .frame(width: 10)
                    .padding(.trailing, -2)
                    .accessibilityHidden(true)
            }
            #endif
            Text(title).foregroundStyle(.primary).textCase(.none)
            Button(action: info) { Image(systemName: "info.circle") }
                .buttonStyle(.plain).noFocusRingCompat()
                .foregroundStyle(.secondary).accessibilityLabel("Info")
                .infoPopoverAnchor(anchorID)
            #if os(iOS)
            if let isExpanded {
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                    .accessibilityHidden(true)
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .onTapGesture {
            guard let isExpanded else { return }
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.wrappedValue.toggle() }
        }
        .accessibilityAddTraits(isExpanded == nil ? [] : .isButton)
    }
}
