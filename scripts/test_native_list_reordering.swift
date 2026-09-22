import AppKit
import SwiftUI

@MainActor private final class DragInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .move
    var draggingLocation = NSPoint.zero
    var draggedImageLocation = NSPoint.zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingSequenceNumber = 1
    var draggingFormation = NSDraggingFormation.none
    var animatesToDestination = false
    let draggingItem = NSDraggingItem(pasteboardWriter: NSPasteboardItem())
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight = NSSpringLoadingHighlight.none
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        block(draggingItem, 0, &stop)
    }
    func setID(_ id: UUID) {
        draggingPasteboard.clearContents()
        draggingPasteboard.setString(id.uuidString, forType: MacReorderableList.Coordinator.dragType)
    }
}

@main @MainActor struct NativeListTests {
    struct Item: Identifiable { let id: UUID }
    static func row(_ id: UUID, movable: Bool = true, height: CGFloat? = nil) -> MacListRow {
        MacListRow(id, movable: movable) {
            HStack {
                VStack(alignment: .leading) {
                    Text(id.uuidString).font(.headline)
                    Text("A wrapping row description used to exercise real native cell layout.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("Enabled", isOn: .constant(true)).labelsHidden().toggleStyle(.switch)
            }
            .padding(16)
            .frame(height: height)
        }
    }
    static func section(_ name: String, _ ids: [UUID], accepts: Bool = true) -> MacListSection {
        MacListSection(id: name, header: AnyView(Text(name)), rows: ids.map { row($0, movable: accepts) },
                       acceptsMoves: accepts)
    }
    static func sizedSection(_ name: String, _ ids: [UUID], heights: [CGFloat]) -> MacListSection {
        precondition(!heights.isEmpty)
        return MacListSection(id: name, header: AnyView(Text(name)), rows: ids.enumerated().map {
            row($0.element, height: heights[$0.offset % heights.count])
        })
    }
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    static func settle(_ host: NSView) async throws {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 80_000_000)
        host.layoutSubtreeIfNeeded()
    }

    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let ids = (0..<6).map { _ in UUID() }
        let base = [section("a", Array(ids.prefix(4))), section("b", Array(ids.suffix(2))), section("empty", [])]
        var cases = 0
        for source in 0..<4 {
            for index in 0...4 {
                let move = MacListMove.proposed(itemID: ids[source], sectionID: "a", childIndex: index, sections: base)
                var expected = Array(ids.prefix(4))
                let item = expected.remove(at: source)
                expected.insert(item, at: index > source ? index - 1 : index)
                precondition(move?.orderedIDs == (expected == Array(ids.prefix(4)) ? nil : expected))
                cases += 1
            }
            for index in 0...2 {
                let move = MacListMove.proposed(itemID: ids[source], sectionID: "b", childIndex: index, sections: base)!
                var expected = Array(ids.suffix(2)); expected.insert(ids[source], at: index)
                precondition(move.orderedIDs == expected)
                cases += 1
            }
        }
        precondition(MacListMove.proposed(itemID: ids[0], sectionID: "empty", childIndex: -1, sections: base)?.orderedIDs == [ids[0]])
        precondition(MacListMove.proposed(itemID: ids[0], sectionID: "b", childIndex: -1, sections: base)?.orderedIDs == [ids[4], ids[5], ids[0]])
        for index in [-2, 5, Int.max] {
            precondition(MacListMove.proposed(itemID: ids[0], sectionID: "a", childIndex: index, sections: base) == nil)
        }
        precondition(MacListMove.proposed(itemID: UUID(), sectionID: "a", childIndex: 0, sections: base) == nil)
        precondition(MacListMove.proposed(itemID: ids[0], sectionID: "missing", childIndex: 0, sections: base) == nil)
        let fixedID = UUID()
        let fixed = section("foreign", [fixedID], accepts: false)
        precondition(MacListMove.proposed(itemID: ids[0], sectionID: "foreign", childIndex: 0, sections: base + [fixed]) == nil)
        precondition(MacListMove.proposed(itemID: fixedID, sectionID: "a", childIndex: 0, sections: base + [fixed]) == nil)

        // Search and enabled-only lists replace visible slots without moving hidden items.
        let items = ids.map(Item.init)
        let encoded = ListDisplayOrder.saving([items[3], items[0]], in: items)
        precondition(ListDisplayOrder.sorted(items, order: encoded).map(\.id) == [ids[3], ids[1], ids[2], ids[0], ids[4], ids[5]])
        let defaults = UserDefaults(suiteName: "wblock.native-list-tests.\(UUID())")!
        defaults.set(encoded, forKey: "order")
        precondition(ListDisplayOrder.sorted(items, order: defaults.data(forKey: "order")!).map(\.id) == [ids[3], ids[1], ids[2], ids[0], ids[4], ids[5]])
        defaults.removeObject(forKey: "order")

        var commits: [MacListMove] = []
        func list(_ sections: [MacListSection]) -> MacReorderableList {
            MacReorderableList(sections: sections, header: AnyView(Text("Statistics").padding(16)),
                              onMove: { commits.append($0); return true })
        }
        let model = list(base + [fixed])
        let host = NSHostingView(rootView: model)
        host.frame = NSRect(x: 0, y: 0, width: 540, height: 480)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        try await settle(host)
        let outlines = descendants(host).compactMap { $0 as? NSOutlineView }
        precondition(outlines.count == 1)
        let outline = outlines[0]
        let coordinator = outline.delegate as! MacReorderableList.Coordinator
        precondition(outline.enclosingScrollView != nil && outline.draggingDestinationFeedbackStyle == .gap)
        precondition(outline.verticalMotionCanBeginDrag && !outline.allowsMultipleSelection)
        precondition(outline.registeredDraggedTypes.contains(MacReorderableList.Coordinator.dragType))
        let parentA = coordinator.outlineView(outline, child: 1, ofItem: nil)
        let parentB = coordinator.outlineView(outline, child: 2, ofItem: nil)
        let emptyParent = coordinator.outlineView(outline, child: 3, ofItem: nil)
        let foreignParent = coordinator.outlineView(outline, child: 4, ofItem: nil)
        let firstRow = coordinator.outlineView(outline, child: 0, ofItem: parentA)
        let foreignRow = coordinator.outlineView(outline, child: 0, ofItem: foreignParent)
        precondition(coordinator.outlineView(outline, pasteboardWriterForItem: parentA) == nil)
        precondition(coordinator.outlineView(outline, pasteboardWriterForItem: foreignRow) == nil)
        precondition(coordinator.outlineView(outline, pasteboardWriterForItem: firstRow) != nil)
        // Collapse is owned by the SwiftUI header now: foreign rows simply are
        // or are not part of the section, so the outline never draws a cell and
        // ordinary sections stay expanded without native collapse.
        precondition(outline.isItemExpanded(parentA))
        precondition(outline.isItemExpanded(foreignParent))
        precondition(outline.numberOfChildren(ofItem: foreignParent) == 1)

        let mouseDown = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                          timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1)!
        let rowIndex = outline.row(forItem: firstRow)
        var imageOffset = NSPoint.zero
        let nativeImage = outline.dragImageForRows(with: IndexSet(integer: rowIndex), tableColumns: outline.tableColumns,
                                                  event: mouseDown, offset: &imageOffset)
        let cell = outline.view(atColumn: 0, row: rowIndex, makeIfNecessary: true)!
        precondition(nativeImage.size.width >= cell.bounds.width - 1)
        precondition(nativeImage.size.height >= cell.bounds.height - 1)
        precondition(nativeImage.tiffRepresentation != nil, "The default native image must contain the whole hosted row")

        let firstNode = firstRow as! MacReorderableList.Coordinator.Node
        let secondNode = coordinator.outlineView(outline, child: 1, ofItem: parentA) as! MacReorderableList.Coordinator.Node
        let lastNode = coordinator.outlineView(outline, child: 3, ofItem: parentA) as! MacReorderableList.Coordinator.Node
        precondition(firstNode.cardShape?.roundsTop == true && firstNode.cardShape?.roundsBottom == false)
        precondition(secondNode.cardShape?.roundsTop == false && secondNode.cardShape?.roundsBottom == false)
        precondition(lastNode.cardShape?.roundsTop == false && lastNode.cardShape?.roundsBottom == true)
        precondition(firstNode.showsSeparator && !lastNode.showsSeparator)
        outline.selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
        precondition(outline.selectedRow == rowIndex, "Custom card styling must retain native selection")

        let info = DragInfo()
        defer { info.draggingPasteboard.releaseGlobally() }
        info.draggingSource = outline
        info.setID(ids[0])
        coordinator.beginDragging()
        for _ in 0..<100 {
            precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: parentB, proposedChildIndex: 0) == .move)
            precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: emptyParent, proposedChildIndex: -1) == .move)
        }
        precondition(commits.isEmpty, "Hover must not change order or category")
        precondition(info.animatesToDestination)
        precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: foreignParent, proposedChildIndex: 0).isEmpty)
        precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: nil, proposedChildIndex: 0).isEmpty)
        info.draggingSource = NSOutlineView()
        precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: parentB, proposedChildIndex: 0).isEmpty)
        info.draggingSource = nil
        precondition(!coordinator.outlineView(outline, acceptDrop: info, item: parentB, childIndex: 0))
        info.draggingSource = outline
        let destinationRow = coordinator.outlineView(outline, child: 0, ofItem: parentB)
        let destinationFrame = outline.rect(ofRow: outline.row(forItem: destinationRow))
        info.draggingLocation = outline.convert(NSPoint(x: 30, y: destinationFrame.minY + 1), to: nil)
        precondition(coordinator.proposal(info, item: destinationRow, index: -1)?.orderedIDs == [ids[0], ids[4], ids[5]])
        info.draggingLocation = outline.convert(NSPoint(x: 30, y: destinationFrame.maxY - 1), to: nil)
        precondition(coordinator.proposal(info, item: destinationRow, index: -1)?.orderedIDs == [ids[4], ids[0], ids[5]])
        coordinator.endDragging()
        try await settle(host)
        precondition(commits.isEmpty, "Cancellation and outside drops must leave the model untouched")

        coordinator.beginDragging()
        precondition(coordinator.outlineView(outline, acceptDrop: info, item: parentB, childIndex: 0))
        precondition(commits == [MacListMove(itemID: ids[0], sectionID: "b", orderedIDs: [ids[0], ids[4], ids[5]])])
        precondition(outline.parent(forItem: firstRow) as? MacReorderableList.Coordinator.Node === parentB as? MacReorderableList.Coordinator.Node)
        precondition(coordinator.outlineView(outline, numberOfChildrenOfItem: parentA) == 3)
        precondition(coordinator.outlineView(outline, numberOfChildrenOfItem: parentB) == 3)
        precondition(outline.row(forItem: firstRow) >= 0, "The moved native row must have a landing position before returning")
        precondition(info.draggingItem.draggingFrame == outline.rect(ofRow: outline.row(forItem: firstRow)))
        precondition(info.draggingItem.draggingFrame != outline.rect(ofRow: rowIndex), "The drag image must land at the destination, not its original slot")
        precondition(!coordinator.outlineView(outline, acceptDrop: info, item: parentB, childIndex: 0), "Commit once per session")
        precondition(secondNode.cardShape?.roundsTop == true, "Moving the first row must round the new source boundary")
        precondition(firstNode.cardShape?.roundsTop == true && firstNode.cardShape?.roundsBottom == false)
        precondition(outline.item(atRow: outline.selectedRow) as? MacReorderableList.Coordinator.Node === firstNode)
        coordinator.endDragging()
        try await settle(host)

        precondition(!coordinator.outlineView(outline, acceptDrop: info, item: parentB, childIndex: 0), "An ended session cannot be replayed")

        coordinator.beginDragging()
        precondition(coordinator.outlineView(outline, validateDrop: info, proposedItem: parentB, proposedChildIndex: 3) == .move)
        precondition(coordinator.outlineView(outline, acceptDrop: info, item: parentB, childIndex: 3))
        precondition(commits.last?.orderedIDs == [ids[4], ids[5], ids[0]])
        precondition(info.draggingItem.draggingFrame == outline.rect(ofRow: outline.row(forItem: firstRow)))
        precondition(firstNode.cardShape?.roundsBottom == true && firstNode.cardShape?.roundsTop == false)
        coordinator.endDragging()
        try await settle(host)

        // A deletion received during a drag invalidates its payload without reloading shadow rows.
        coordinator.beginDragging()
        let oldCount = outline.numberOfRows
        let deleted = [section("a", Array(ids[1..<4])), base[1], base[2], fixed]
        host.rootView = list(deleted)
        try await settle(host)
        precondition(outline.numberOfRows == oldCount)
        precondition(!coordinator.outlineView(outline, acceptDrop: info, item: parentB, childIndex: 0))
        coordinator.endDragging()
        try await settle(host)
        precondition(outline.numberOfRows == oldCount - 1)
        precondition(outline.selectedRow == -1, "Deleting the selected row must not select its former neighbor")
        precondition(commits.count == 2)

        // Exercise native row reuse and scrolling with substantially more than one viewport.
        let many = (0..<120).map { _ in UUID() }
        let scrollHeights: [CGFloat] = [120, 82, 48, 120, 82]
        host.rootView = list([sizedSection("long", many, heights: scrollHeights)])
        try await settle(host)
        precondition(outline.numberOfRows == many.count + 2)
        outline.scrollRowToVisible(outline.numberOfRows - 1)
        try await settle(host)
        precondition(outline.visibleRect.minY > 0)
        let scrollView = outline.enclosingScrollView!
        precondition(scrollView.contentView.contentInsets.bottom == 16,
                     "The bottom list inset must match the horizontal card inset")
        let measuredBottom = outline.convert(outline.rect(ofRow: outline.numberOfRows - 1), to: nil)
        let measuredClip = scrollView.contentView.convert(scrollView.contentView.bounds, to: nil)
        let measuredGap = measuredBottom.minY - measuredClip.minY
        print("native mixture initial bottomGap=\(measuredGap)")
        precondition(abs(measuredGap - 16) <= 1,
                     "initial mixed-height bottom clearance must be 16, measured \(measuredGap)")

        // Keep the identity and scroll position, then asynchronously shrink
        // the actual measured rows. This bypasses structure-clamp logic.
        host.rootView = list([sizedSection("long", many, heights: [48, 82, 120])])
        try await settle(host)
        let collapsedBottom = outline.convert(outline.rect(ofRow: outline.numberOfRows - 1), to: nil)
        let collapsedClip = scrollView.contentView.convert(scrollView.contentView.bounds, to: nil)
        let collapsedGap = collapsedBottom.minY - collapsedClip.minY
        print("native mixture shrunk bottomGap=\(collapsedGap)")
        precondition(abs(collapsedGap - 16) <= 1,
                     "asynchronously shrunk rows must clamp bottom clearance to 16, measured \(collapsedGap)")
        let bottom = outline.item(atRow: outline.numberOfRows - 1)!
        let writer = coordinator.outlineView(outline, pasteboardWriterForItem: bottom) as! NSPasteboardItem
        precondition(writer.string(forType: MacReorderableList.Coordinator.dragType) == many.last!.uuidString)

        // Shrinking a scrolled document must clamp to AppKit's real document
        // bounds, including a regional/category collapse at the bottom.
        let few = Array(many.prefix(3))
        host.rootView = list([section("long", few)])
        try await settle(host)
        let shortScroll = outline.enclosingScrollView!
        let shortOrigin = shortScroll.contentView.bounds.origin
        let shortConstrained = shortScroll.contentView.constrainBoundsRect(shortScroll.contentView.bounds).origin
        precondition(abs(shortOrigin.y - shortConstrained.y) < 1,
                     "shrinking a native list must clamp its clip origin")
        // Expansion/reorder while scrolled must preserve the current viewport
        // rather than jumping back to the first row.
        shortScroll.contentView.scroll(to: NSPoint(x: shortOrigin.x, y: shortOrigin.y))
        let viewportBeforeExpansion = shortScroll.contentView.bounds.origin
        host.rootView = list([section("long", [UUID()] + many)])
        try await settle(host)
        let viewportAfterExpansion = shortScroll.contentView.bounds.origin
        precondition(abs(viewportAfterExpansion.y - viewportBeforeExpansion.y) < 1,
                     "rebuilding an expanded category must preserve the scrolled viewport")

        // Rapid filter-like replacements must remain valid for both empty and
        // non-empty results, including returning to a short list at the top.
        for result in [Array(many.prefix(1)), [], Array(many.suffix(2)), []] {
            host.rootView = list([section("long", result)])
            try await settle(host)
            let current = shortScroll.contentView.bounds
            let constrained = shortScroll.contentView.constrainBoundsRect(current)
            precondition(abs(current.origin.y - constrained.origin.y) < 1,
                         "rapid result replacement must keep a valid clip origin")
        }

        host.rootView = list([section("long", [UUID()] + many)])
        try await settle(host)
        outline.scrollRowToVisible(0)
        try await settle(host)
        precondition(outline.visibleRect.minY == 0)
        for width in [480.0, 900.0] {
            host.setFrameSize(NSSize(width: width, height: 480))
            try await settle(host)
            precondition(outline.numberOfRows == many.count + 3)
            let visible = outline.rows(in: outline.visibleRect)
            for rowIndex in visible.location..<NSMaxRange(visible) {
                let rect = outline.rect(ofRow: rowIndex)
                precondition(rect.height > 0 && rect.width <= width)
                precondition(outline.view(atColumn: 0, row: rowIndex, makeIfNecessary: true) != nil)
            }
        }
        let multilingualID = UUID()
        var regional = MacListSection(id: "regional", header: AnyView(Text("Regional")), rows: [
            MacListRow(decoration: "en") { Text("English") },
            MacListRow(multilingualID, movable: false, group: "en") { Text("Multilingual filter") },
            MacListRow(decoration: "fr") { Text("French") },
            MacListRow(multilingualID, movable: false, group: "fr") { Text("Multilingual filter") }
        ], acceptsMoves: false)
        host.rootView = list([regional])
        try await settle(host)
        regional = MacListSection(id: regional.id, header: AnyView(Text("Updated regional metadata")), rows: regional.rows,
                                  acceptsMoves: false)
        host.rootView = list([regional])
        try await settle(host)
        precondition(outline.numberOfRows == 6)
        precondition(outline.item(atRow: 3) as? MacReorderableList.Coordinator.Node !== outline.item(atRow: 5) as? MacReorderableList.Coordinator.Node)

        let wrappingRows = [MacListRow(UUID()) {
            HStack {
                Text(String(repeating: "A long custom filter description must wrap without clipping. ", count: 14))
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch)
            }.padding(16)
        }, row(UUID())]
        host.rootView = list([MacListSection(id: "wrapping", header: AnyView(Text("Wrapping")), rows: wrappingRows)])
        var heights: [CGFloat] = []
        for width in [480.0, 900.0, 480.0] {
            host.setFrameSize(NSSize(width: width, height: 600))
            try await settle(host)
            let first = outline.rect(ofRow: 2)
            let cell = outline.view(atColumn: 0, row: 2, makeIfNecessary: true)!
            precondition(first.height > outline.rect(ofRow: 3).height)
            precondition(abs(first.height - cell.fittingSize.height) < 1, "Every line must fit inside its draggable native row")
            precondition(outline.rect(ofRow: 3).minY >= first.maxY, "Wrapped rows must not overlap")
            heights.append(first.height)
        }
        precondition(heights[0] > heights[1] && abs(heights[0] - heights[2]) < 1)
        print("PASS \(cases) insertion cases, filtered persistence, native source restrictions, hover/cancel/commit, stale deletion, header disclosure, selection, card boundaries, wrapping, scrolling, row reuse, shrink clamping and rapid result replacement")
    }
}
