#if os(macOS)
import AppKit
import SwiftUI

/// Adjacent native cells share a material card without sharing a drag view.
struct MacListCardShape: Shape {
    var roundsTop: Bool
    var roundsBottom: Bool

    func path(in rect: CGRect) -> Path {
        let radius = min(12, min(rect.width, rect.height) / 2)
        var path = Path(roundedRect: rect, cornerRadius: radius)
        if !roundsTop { path.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: radius)) }
        if !roundsBottom { path.addRect(CGRect(x: rect.minX, y: rect.maxY - radius, width: rect.width, height: radius)) }
        return path
    }
}

/// Give SwiftUI a finite width when AppKit asks for the row's intrinsic height.
/// An unconstrained hosting view reports a single-line height even when its text wraps.
final class MacListHostingView: NSHostingView<AnyView> {
    private var content = AnyView(EmptyView())

    func setContent(_ content: AnyView) {
        self.content = content
        updateWidth()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = frame.width != newSize.width
        super.setFrameSize(newSize)
        if widthChanged { updateWidth() }
    }

    private func updateWidth() {
        rootView = bounds.width > 0 ? AnyView(content.frame(width: bounds.width)) : content
        invalidateIntrinsicContentSize()
    }
}

struct MacListRow {
    enum ID: Hashable { case item(UUID, String?), decoration(String) }
    let id: ID
    let movableID: UUID?
    let content: AnyView

    init<Content: View>(_ id: UUID, movable: Bool = true, group: String? = nil, @ViewBuilder content: () -> Content) {
        self.id = .item(id, group)
        movableID = movable ? id : nil
        self.content = AnyView(content())
    }

    init<Content: View>(decoration id: String, @ViewBuilder content: () -> Content) {
        self.id = .decoration(id)
        movableID = nil
        self.content = AnyView(content())
    }
}

struct MacListSection {
    let id: String
    let header: AnyView
    var rows: [MacListRow]
    var acceptsMoves = true
}

/// Rows that cannot move never enter AppKit's drag machinery. Refusing only
/// in `pasteboardWriterForItem` is too late: by then the outline has hidden the
/// pressed row for its drag image, and with no session to end, nothing shows
/// it again until another drag finishes (#834).
final class MacReorderableOutlineView: NSOutlineView {
    var canDragRow: (Int) -> Bool = { _ in true }

    override func canDragRows(with rowIndexes: IndexSet, at mouseDownPoint: NSPoint) -> Bool {
        rowIndexes.allSatisfy(canDragRow)
            && super.canDragRows(with: rowIndexes, at: mouseDownPoint)
    }
}

struct MacListMove: Equatable {
    let itemID: UUID
    let sectionID: String
    let orderedIDs: [UUID]

    static func proposed(itemID: UUID, sectionID: String, childIndex: Int,
                         sections: [MacListSection]) -> Self? {
        guard sections.contains(where: { $0.rows.contains(where: { $0.movableID == itemID }) }),
              let destination = sections.first(where: { $0.id == sectionID }),
              destination.acceptsMoves else { return nil }
        let rows = destination.rows
        let index = childIndex == NSOutlineViewDropOnItemIndex ? rows.count : childIndex
        guard (0...rows.count).contains(index), rows.allSatisfy({ $0.movableID != nil }) else { return nil }
        let oldIDs = rows.compactMap(\.movableID)
        let insertion = index - oldIDs.prefix(index).filter { $0 == itemID }.count
        var ids = oldIDs.filter { $0 != itemID }
        ids.insert(itemID, at: insertion)
        guard ids != oldIDs else { return nil }
        return Self(itemID: itemID, sectionID: sectionID, orderedIDs: ids)
    }
}

/// AppKit owns the drag session, row images, insertion gap, disclosure, and scrolling.
/// SwiftUI supplies cell content and commits a move only after an accepted drop.
struct MacReorderableList: NSViewRepresentable {
    var sections: [MacListSection]
    let header: AnyView
    var emptyContent: AnyView? = nil
    let onMove: (MacListMove) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        // Keep the old SwiftUI list's breathing room under the last card. The
        // inset belongs to the content view, which owns the document geometry.
        scroll.contentView.contentInsets.bottom = 36
        let outline = MacReorderableOutlineView()
        outline.canDragRow = { [weak coordinator = context.coordinator, weak outline] row in
            guard let coordinator, let outline, let item = outline.item(atRow: row) else { return false }
            return coordinator.movableID(for: item) != nil
        }
        let column = NSTableColumn(identifier: .init("content"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .plain
        outline.backgroundColor = .clear
        outline.indentationPerLevel = 0
        outline.intercellSpacing = .zero
        outline.selectionHighlightStyle = .none
        outline.allowsEmptySelection = true
        outline.allowsMultipleSelection = false
        outline.usesAutomaticRowHeights = true
        outline.rowHeight = 92
        outline.floatsGroupRows = false
        outline.verticalMotionCanBeginDrag = true
        outline.draggingDestinationFeedbackStyle = .gap
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask([], forLocal: false)
        outline.registerForDraggedTypes([Coordinator.dragType])
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        scroll.documentView = outline
        context.coordinator.outline = outline
        context.coordinator.update(self, environment: context.environment)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(self, environment: context.environment)
    }

    @MainActor final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        static let dragType = NSPasteboard.PasteboardType("app.wblock.native-list-row")

        final class Node {
            enum ID: Hashable { case header, empty, section(String), row(MacListRow.ID) }
            let id: ID
            var content: AnyView
            var children: [Node] = []
            var cardShape: MacListCardShape?
            var showsSeparator = false
            init(_ id: ID, content: AnyView) { self.id = id; self.content = content }
        }

        var model: MacReorderableList
        weak var outline: NSOutlineView?
        private var environment = EnvironmentValues()
        private var roots: [Node] = []
        private var structure: [[Node.ID]] { roots.map { [$0.id] + $0.children.map(\.id) } }
        private var dragging = false
        private var accepted = false
        private var updating = false

        init(_ model: MacReorderableList) { self.model = model }

        func update(_ model: MacReorderableList, environment: EnvironmentValues) {
            self.model = model
            self.environment = environment
            // Never invalidate AppKit's shadow rows during its drag tracking loop.
            // Drop validation still consults the latest model, including deletions.
            guard !dragging, let outline else { return }
            updating = true
            defer { updating = false }
            let previous = structure
            let existing = Dictionary(uniqueKeysWithValues: roots.flatMap { [$0] + $0.children }.map { ($0.id, $0) })
            func node(_ id: Node.ID, _ content: AnyView) -> Node {
                let value = existing[id] ?? Node(id, content: content)
                value.content = content
                return value
            }
            roots = [node(.header, model.header)]
            for section in model.sections {
                let parent = node(.section(section.id), AnyView(section.header
                    .font(.headline).padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)))
                parent.children = section.rows.map { node(.row($0.id), $0.content) }
                updateCardEdges(in: parent)
                roots.append(parent)
            }
            if let empty = model.emptyContent { roots.append(node(.empty, empty)) }

            if previous != structure {
                let selected = outline.selectedRow >= 0 ? outline.item(atRow: outline.selectedRow) as? Node : nil
                outline.reloadData()
                // reloadData leaves expandable sections collapsed, and AppKit
                // refuses collapseItem once the outline cell is hidden, so the
                // rows a section exposes are exactly the rows it gets.
                for section in model.sections {
                    guard let node = sectionNode(section.id) else { continue }
                    outline.expandItem(node)
                }
                if let selected {
                    let row = outline.row(forItem: selected)
                    if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
                }
            }
            // AppKit animates row-height changes by default; after a drop the
            // settling rows should snap so separators do not trail behind.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                outline.noteHeightOfRows(withIndexesChanged: refreshVisibleRows())
            }
        }

        @discardableResult
        private func refreshVisibleRows() -> IndexSet {
            guard let outline else { return [] }
            let visible = outline.rows(in: outline.visibleRect)
            guard visible.location != NSNotFound else { return [] }
            let indexes = IndexSet(integersIn: visible.location..<NSMaxRange(visible))
            for row in indexes {
                guard let node = outline.item(atRow: row) as? Node,
                      let view = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? MacListHostingView else { continue }
                view.setContent(hosted(node))
            }
            return indexes
        }

        private func updateCardEdges(in parent: Node) {
            for (index, child) in parent.children.enumerated() {
                child.cardShape = MacListCardShape(roundsTop: index == 0, roundsBottom: index == parent.children.count - 1)
                // Regional language headings have breathing room on both sides.
                child.showsSeparator = index + 1 < parent.children.count
                    && isContentRow(child) && isContentRow(parent.children[index + 1])
            }
        }

        private func isContentRow(_ node: Node) -> Bool {
            if case .row(.item) = node.id { return true }
            return false
        }

        // Reused cells host a different row each time they scroll in. Keying
        // the content by row identity makes SwiftUI rebuild the switch instead
        // of animating it from the previous row's state (#831).
        private func hosted(_ node: Node) -> AnyView {
            AnyView(Group {
                if let shape = node.cardShape {
                    node.content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: shape)
                        .overlay(alignment: .bottom) {
                            if node.showsSeparator { Divider().padding(.leading, 16) }
                        }
                        .padding(.horizontal, 16)
                } else {
                    node.content
                }
            }
            .id(node.id)
            .environment(\.self, environment))
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? Node)?.children.count ?? roots.count
        }
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            ((item as? Node)?.children ?? roots)[index]
        }
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? Node else { return false }
            if case .section = node.id { return true }
            return false
        }
        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            guard let node = item as? Node else { return false }
            if case .section = node.id { return true }
            return false
        }
        // The disclosure lives in the SwiftUI header (ListCategoryHeader) where
        // it lines up with the other category titles. AppKit's own outline cell
        // would pin a triangle to the row's leading edge, half outside the
        // padded content and nearly impossible to hit.
        func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
            false
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            guard let node = item as? Node, case .row = node.id else { return false }
            return true
        }
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("hosted-row")
            let view = outlineView.makeView(withIdentifier: identifier, owner: nil) as? MacListHostingView
                ?? MacListHostingView(rootView: AnyView(EmptyView()))
            view.identifier = identifier
            view.setContent(hosted(node))
            return view
        }

        private func sectionNode(_ id: String) -> Node? { roots.first { $0.id == .section(id) } }

        private func section(for item: Any?) -> MacListSection? {
            guard let node = item as? Node, case .section(let id) = node.id else { return nil }
            return model.sections.first { $0.id == id }
        }
        func movableID(for item: Any) -> UUID? {
            guard let node = item as? Node, case .row(let id) = node.id else { return nil }
            return model.sections.lazy.flatMap(\.rows).first { $0.id == id }?.movableID
        }
        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let id = movableID(for: item) else { return nil }
            let writer = NSPasteboardItem()
            writer.setString(id.uuidString, forType: Self.dragType)
            return writer
        }
        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                         willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
            beginDragging()
        }
        func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                         endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            endDragging()
        }

        func beginDragging() {
            dragging = true
            accepted = false
        }
        func endDragging() {
            dragging = false
            accepted = false
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.update(self.model, environment: self.environment)
            }
        }

        private func destination(_ info: NSDraggingInfo, item: Any?, index: Int) -> (node: Node, index: Int)? {
            guard let node = item as? Node else { return nil }
            if let section = section(for: node) {
                return (node, index == NSOutlineViewDropOnItemIndex ? section.rows.count : index)
            }
            // A drop over a leaf means insertion beside it, never making that row a parent.
            guard index == NSOutlineViewDropOnItemIndex, let outline,
                  case .row(let id) = node.id, let parent = outline.parent(forItem: node) as? Node,
                  let section = section(for: parent),
                  let childIndex = section.rows.firstIndex(where: { $0.id == id }) else { return nil }
            let row = outline.row(forItem: node)
            guard row >= 0 else { return nil }
            let point = outline.convert(info.draggingLocation, from: nil)
            return (parent, childIndex + (point.y > outline.rect(ofRow: row).midY ? 1 : 0))
        }

        func proposal(_ info: NSDraggingInfo, item: Any?, index: Int) -> MacListMove? {
            guard dragging, !accepted, let outline, info.draggingSource as? NSOutlineView === outline,
                  let value = info.draggingPasteboard.string(forType: Self.dragType),
                  let id = UUID(uuidString: value),
                  let source = model.sections.first(where: { $0.rows.contains(where: { $0.movableID == id }) }),
                  source.rows.map({ Node.ID.row($0.id) }) == sectionNode(source.id)?.children.map(\.id),
                  let target = destination(info, item: item, index: index),
                  let section = section(for: target.node),
                  section.rows.map({ Node.ID.row($0.id) }) == target.node.children.map(\.id) else { return nil }
            return MacListMove.proposed(itemID: id, sectionID: section.id, childIndex: target.index, sections: model.sections)
        }
        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                         proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard proposal(info, item: item, index: index) != nil,
                  let target = destination(info, item: item, index: index) else { return [] }
            info.animatesToDestination = true
            outlineView.setDropItem(target.node, dropChildIndex: target.index)
            return .move
        }
        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                         item: Any?, childIndex index: Int) -> Bool {
            guard let move = proposal(info, item: item, index: index),
                  let sourceIndex = model.sections.firstIndex(where: { $0.rows.contains(where: { $0.movableID == move.itemID }) }),
                  let destinationIndex = model.sections.firstIndex(where: { $0.id == move.sectionID }),
                  let oldIndex = model.sections[sourceIndex].rows.firstIndex(where: { $0.movableID == move.itemID }),
                  let newIndex = move.orderedIDs.firstIndex(of: move.itemID),
                  let source = sectionNode(model.sections[sourceIndex].id),
                  let destination = sectionNode(move.sectionID),
                  model.onMove(move) else { return false }
            let node = source.children[oldIndex]
            accepted = true
            let row = model.sections[sourceIndex].rows.remove(at: oldIndex)
            model.sections[destinationIndex].rows.insert(row, at: newIndex)
            source.children.removeAll { $0 === node }
            destination.children.insert(node, at: newIndex)
            updateCardEdges(in: source)
            updateCardEdges(in: destination)
            // The drag image owns the landing animation. Animating the underlying
            // row again exposes its old position for a frame when the image disappears.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                outlineView.moveItem(at: oldIndex, inParent: source, to: newIndex, inParent: destination)
                refreshVisibleRows()
                outlineView.layoutSubtreeIfNeeded()
            }
            let landingRow = outlineView.row(forItem: node)
            let frame = outlineView.rect(ofRow: landingRow)
            info.enumerateDraggingItems(options: [], for: outlineView, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
                item.draggingFrame = frame
            }
            // The row already sits at its destination while the drag image is
            // still flying there, which reads as a duplicate card behind the
            // drop. Keep the row transparent until the image lands, then show
            // it at once so its separator does not lag the drop (#817).
            if landingRow >= 0,
               let landingView = outlineView.view(atColumn: 0, row: landingRow, makeIfNecessary: false) {
                landingView.alphaValue = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.06
                        landingView.animator().alphaValue = 1
                    }
                }
            }
            return true
        }
    }
}
#endif
