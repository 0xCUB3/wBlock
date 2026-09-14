import SwiftUI

@MainActor
final class ListDrag: ObservableObject {
    static let type = "app.wblock.list-row"
    @Published var id: UUID?
    private var session = UUID()

    func begin(_ id: UUID, cancel: @escaping @MainActor () -> Void = {}) -> NSItemProvider {
        self.id = id
        session = UUID()
        let token = session
        let provider = ListDragProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.type, visibility: .ownProcess) { completion in
            completion(Data(id.uuidString.utf8), nil)
            return nil
        }
        provider.onEnd = { [weak self] in
            Task { @MainActor in
                if self?.session == token, self?.id != nil { cancel(); self?.id = nil }
            }
        }
        return provider
    }
}

private final class ListDragProvider: NSItemProvider, @unchecked Sendable {
    var onEnd: (@Sendable () -> Void)?
    deinit { onEnd?() }
}

struct ListDrop: DropDelegate {
    let drag: ListDrag
    var hover: (UUID) -> Void = { _ in }
    let commit: (UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        drag.id != nil && info.hasItemsConforming(to: [ListDrag.type])
    }
    func dropEntered(info: DropInfo) {
        if validateDrop(info: info), let id = drag.id {
            withAnimation(.easeInOut(duration: 0.18)) { hover(id) }
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let id = drag.id else { return false }
        withAnimation(.easeInOut(duration: 0.18)) { commit(id) }
        drag.id = nil
        return true
    }
}

struct ReorderableRows<Item: Identifiable, Row: View>: View where Item.ID == UUID {
    let items: [Item]
    // Global ordering is only needed during a move, never during row layout.
    let allItems: () -> [Item]
    @Binding var order: Data
    @ObservedObject var drag: ListDrag
    let commit: (UUID) -> Void
    @ViewBuilder let row: (Item) -> Row

    private func move(_ source: IndexSet, to destination: Int) {
        guard source.allSatisfy({ items.indices.contains($0) }),
              (0...items.count).contains(destination) else { return }
        var moved = items
        moved.move(fromOffsets: source, toOffset: destination)
        order = ListDisplayOrder.saving(moved, in: allItems())
    }

    var body: some View {
        #if os(iOS)
        // Let List snapshot and move the whole cell with one native drag session.
        ForEach(items) { item in
            row(item)
        }
        .onMove(perform: move)
        #else
        ForEach(items) { item in
            row(item)
                .onDrag {
                    let original = order
                    return drag.begin(item.id) { order = original }
                }
                .onDrop(of: [ListDrag.type], delegate: ListDrop(drag: drag, hover: { id in
                    guard id != item.id,
                          let source = items.firstIndex(where: { $0.id == id }),
                          let target = items.firstIndex(where: { $0.id == item.id }) else { return }
                    move(IndexSet(integer: source), to: target + (source < target ? 1 : 0))
                }, commit: { id in
                    if !items.contains(where: { $0.id == id }),
                       let source = allItems().first(where: { $0.id == id }),
                       let target = items.firstIndex(where: { $0.id == item.id }) {
                        var moved = items
                        moved.insert(source, at: target)
                        order = ListDisplayOrder.saving(moved, in: allItems())
                    }
                    commit(id)
                }))
            if item.id != items.last?.id { Divider().padding(.leading, 16) }
        }
        #endif
    }
}

struct ContentListSection<Header: View, Content: View>: View {
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(iOS)
        Section(content: content, header: header)
        #else
        VStack(alignment: .leading, spacing: 12) {
            header().font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            VStack(spacing: 0, content: content)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        #endif
    }
}

struct ListCategoryHeader: View {
    let title: LocalizedStringKey
    let info: () -> Void
    var drop: ListDrop? = nil
    var anchorID: AnyHashable? = nil
    /// When set, the header gains a trailing chevron and toggles this binding on tap.
    var isExpanded: Binding<Bool>? = nil

    var body: some View {
        #if os(macOS)
        if let drop {
            header.onDrop(of: [ListDrag.type], delegate: drop)
        } else {
            header
        }
        #else
        header
        #endif
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(title).infoPopoverAnchor(anchorID).foregroundStyle(.primary).textCase(.none)
            Button(action: info) { Image(systemName: "info.circle") }
                .buttonStyle(.plain).noFocusRingCompat()
                .foregroundStyle(.secondary).accessibilityLabel("Info")
            if let isExpanded {
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .onTapGesture {
            guard let isExpanded else { return }
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.wrappedValue.toggle() }
        }
        .accessibilityAddTraits(isExpanded == nil ? [] : .isButton)
    }
}
