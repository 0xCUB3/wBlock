import AppKit
import SwiftUI

/// Category headers that a structure change conceals or reveals while
/// scrolled out of view must not keep their previous native row height.
/// Drives the coordinator against a bare scroll and outline view; no window.
@main @MainActor struct NativeListHeaderHeightTests {
    static func row(_ id: UUID) -> MacListRow { MacListRow(id) { Text("Row").padding(16) } }
    static func section(_ id: String, _ rows: [UUID], concealable: Bool = false) -> MacListSection {
        MacListSection(id: id, header: AnyView(Text(id)), rows: rows.map(row), revealsOnlyWhileDragging: concealable)
    }

    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let ads = (0..<12).map { _ in UUID() }, privacy = [UUID()], annoyance = UUID()
        let multipurpose = UUID()
        func model(annoyances: [UUID], privacy: [UUID]) -> MacReorderableList {
            MacReorderableList(sections: [
                section("ads", ads), section("multipurpose", [multipurpose]),
                section("annoyances", annoyances, concealable: true),
                section("privacy", privacy, concealable: true),
            ], header: AnyView(Text("Statistics")), onMove: { _ in false })
        }

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        let outline = MacReorderableOutlineView()
        let column = NSTableColumn(identifier: .init("content"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.intercellSpacing = .zero
        scroll.documentView = outline
        let initial = model(annoyances: [], privacy: privacy)
        let coordinator = MacReorderableList.Coordinator(initial)
        outline.dataSource = coordinator
        outline.delegate = coordinator
        coordinator.outline = outline
        func update(_ list: MacReorderableList) {
            coordinator.update(list, environment: EnvironmentValues())
            scroll.layoutSubtreeIfNeeded()
        }
        update(initial)

        func headerHeight(_ index: Int) -> CGFloat {
            let row = outline.row(forItem: coordinator.outlineView(outline, child: index, ofItem: nil))
            precondition(row >= 0 && !outline.rows(in: outline.visibleRect).contains(row),
                         "The header must be out of view to exercise off-screen invalidation")
            return outline.rect(ofRow: row).height
        }
        precondition(headerHeight(3) < 1, "An empty drag-only header starts concealed")
        update(model(annoyances: [annoyance], privacy: privacy))
        precondition(headerHeight(3) > 20, "An off-screen header must reappear when its section gains a first row")
        precondition(headerHeight(4) > 20)
        update(model(annoyances: [annoyance], privacy: []))
        precondition(headerHeight(4) < 1, "An off-screen header must conceal when its section empties")
        update(model(annoyances: [annoyance], privacy: privacy))
        precondition(headerHeight(4) > 20, "An off-screen header must reappear when its section regains rows")
        print("native list header heights: ok")
    }
}
