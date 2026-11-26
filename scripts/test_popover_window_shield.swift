import SwiftUI
import AppKit

private struct Item: Identifiable { let id: Int }
private final class Model: ObservableObject { @Published var selected: Item? }
private final class Box {
    var buttons: [Int: NSView] = [:]
    let rowIDs = (0..<8).map { _ in UUID() }
}
private struct Marker: NSViewRepresentable {
    let id: Int
    let box: Box
    func makeNSView(context: Context) -> NSView { let view = NSView(); box.buttons[id] = view; return view }
    func updateNSView(_ view: NSView, context: Context) { box.buttons[id] = view }
}
private struct Fixture: View {
    @ObservedObject var model: Model
    let box: Box
    var body: some View {
        HStack(spacing: 120) {
            ForEach([1, 2], id: \.self) { id in
                Button("Info \(id)") { model.selected = Item(id: id) }
                    .background(Marker(id: id, box: box))
                    .infoPopoverAnchor(id)
            }
        }
        .padding(40)
        .infoPresentation(item: $model.selected) { item in
            Text("Info \(item.id)").frame(width: 160, height: 80)
        }
    }
}
private struct ClippedFixture: View {
    @ObservedObject var model: Model
    let box: Box
    var body: some View {
        MacReorderableList(sections: [MacListSection(
            id: "rows", header: AnyView(Text("Lists")), rows: box.rowIDs.enumerated().map { index, id in
                MacListRow(id) {
                    HStack {
                        Text("Row \(index)")
                        Spacer()
                        Button { model.selected = Item(id: index) } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.plain)
                            .background(Marker(id: index, box: box))
                            .infoPopoverAnchor(index)
                    }
                    .padding(16).frame(height: 70)
                }
            })], header: AnyView(EmptyView()), onMove: { _ in false })
            .scrollingUnderToolbar()
            .infoPresentation(item: $model.selected) { _ in Text("Details").frame(width: 420, height: 640) }
    }
}
private struct NameAnchoredRowFixture: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading) {
                    Text("Wide Filter Row")
                        .infoPopoverAnchor(1, capturesClicks: false)
                    Text("Secondary description spanning across the row")
                }
                Spacer(minLength: 0)
                Toggle("", isOn: .constant(true)).labelsHidden()
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .infoPresentation(item: $model.selected) { _ in
            Text("Filter Info").frame(width: 460, height: 640)
        }
    }
}
private struct HeaderPopoverFixture: View {
    @ObservedObject var model: Model
    var body: some View {
        MacReorderableList(
            sections: [MacListSection(id: "s1", header: AnyView(Text("Ads")), rows: [
                MacListRow(UUID()) { Text("Row").padding(16) }
            ])],
            header: AnyView(
                HStack {
                    Button("Safari Rules") { model.selected = Item(id: 99) }
                        .buttonStyle(.plain)
                        .padding(12)
                        .infoPopoverAnchor(99)
                }
                .padding(.vertical, 16)
            ),
            onMove: { _ in false }
        )
        .scrollingUnderToolbar()
        .infoPresentation(item: $model.selected, arrowEdge: .bottom) { _ in
            Text("Safari Rule Capacity").frame(width: 340, height: 420)
        }
    }
}
private extension NSView {
    var descendants: [NSView] { [self] + subviews.flatMap(\.descendants) }
}

@main @MainActor
struct PopoverWindowShieldTests {
    static func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.35)) }
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let model = Model(), box = Box()
        let host = NSHostingView(rootView: Fixture(model: model, box: box))
        let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 540, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        pump()

        func shields() -> [PopoverWindowShieldView] { host.descendants.compactMap { $0 as? PopoverWindowShieldView } }
        func popups() -> [NSWindow] { NSApp.windows.filter { $0 !== window && $0.isVisible } }
        precondition(shields().isEmpty && popups().isEmpty, "idle anchors must not shield or show a popup")

        // Exercise the repaired single-host path before its first AppKit readiness callback.
        model.selected = Item(id: 1)
        model.selected = Item(id: 2)
        model.selected = Item(id: 1)
        pump()
        precondition(model.selected?.id == 1, "rapid A->B->A must retain the final selection")
        precondition(shields().count == 1, "rapid A->B->A must install one shield")
        precondition(popups().count == 1, "rapid A->B->A must show exactly one popup")
        let shield = shields()[0]
        let button = box.buttons[1]!
        precondition(shield.bounds.contains(shield.convert(button.bounds, from: button)),
                     "the page-level host must contain the info button")

        // Switching an already-open popup must reuse its host. A delayed
        // dismissal from the first item must not close the second item.
        let dismissFirst = shield.dismiss
        model.selected = Item(id: 2)
        pump()
        precondition(model.selected?.id == 2 && popups().count == 1,
                     "retargeting an open popup must retain the new selection")
        dismissFirst()
        pump()
        precondition(model.selected?.id == 2 && popups().count == 1,
                     "a stale dismissal must not close the current popup")
        model.selected = nil
        pump()
        precondition(shields().isEmpty && popups().isEmpty, "dismissal must remove the shield")

        // Cancellation before readiness must leave the host idle, then reopening must work.
        model.selected = Item(id: 2)
        model.selected = nil
        pump()
        precondition(model.selected == nil && shields().isEmpty && popups().isEmpty, "cancellation before readiness must leave no popup or shield")
        model.selected = Item(id: 2)
        pump()
        precondition(model.selected?.id == 2 && shields().count == 1 && popups().count == 1, "reopening after cancellation must present one popup")
        let reopened = shields()[0]
        let reopenedButton = box.buttons[2]!
        precondition(reopened.bounds.contains(reopened.convert(reopenedButton.bounds, from: reopenedButton)),
                     "the reopened page-level host must contain its info button")

        model.selected = nil
        pump()
        precondition(shields().isEmpty && popups().isEmpty, "teardown must restore the idle host")

        let clippedModel = Model(), clippedBox = Box()
        let clippedHost = NSHostingView(rootView: ClippedFixture(model: clippedModel, box: clippedBox))
        window.contentView = clippedHost
        pump()
        let outline = clippedHost.descendants.compactMap { $0 as? NSOutlineView }.first!
        let listScroll = outline.enclosingScrollView!
        for topEdge in [false, true] {
            outline.scrollRowToVisible(7)
            pump()
            let marker = clippedBox.buttons[5]!
            let rect = marker.convert(marker.bounds, to: outline)
            let y = topEdge ? rect.minY + 4 : rect.maxY - 4 - listScroll.contentView.bounds.height
            listScroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            listScroll.reflectScrolledClipView(listScroll.contentView)
            pump()
            let button = clippedBox.buttons[5]!
            let visible = button.bounds.intersection(button.visibleRect)
            precondition(!visible.isEmpty && visible.height < button.bounds.height, "fixture must clip the info button")
            let point = button.convert(NSPoint(x: visible.midX, y: visible.midY), to: nil)
            let hit = listScroll.hitTest(listScroll.superview!.convert(point, from: nil))
            precondition(hit?.isDescendant(of: outline) == true, "the visible part of a clipped row must receive clicks, even inside the content inset")
            clippedModel.selected = Item(id: 5)
            pump()
            precondition(clippedModel.selected?.id == 5 && popups().count == 1,
                         "a partially visible info button must open its native popover at either viewport edge")
            let popup = popups()[0], frame = popups()[0].frame
            pump()
            precondition(popup.frame == frame, "the tall popover must retain its settled placement")
            clippedModel.selected = nil
            pump()
            precondition(popups().isEmpty, "a clipped-anchor popup must dismiss normally")
        }

        // Keep the original shield behavior checks in the same one-main standalone fixture.
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let popup = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let standaloneShield = PopoverWindowShieldView()
        var dismissals = 0
        standaloneShield.dismiss = { dismissals += 1 }
        precondition(!standaloneShield.consume(.leftMouseDown, in: parent))
        parent.contentView = standaloneShield
        for event in [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown] {
            precondition(!standaloneShield.consume(event, in: parent))
            precondition(!standaloneShield.consume(event, in: popup))
        }
        precondition(dismissals == 3)
        precondition(standaloneShield.consume(.scrollWheel, in: parent) && dismissals == 3)
        precondition(!standaloneShield.consume(.scrollWheel, in: popup))
        precondition(!standaloneShield.consume(.leftMouseDown, in: nil))
        precondition(!standaloneShield.consume(.keyDown, in: parent))
        parent.contentView = NSView()
        precondition(standaloneShield.window == nil && !standaloneShield.consume(.leftMouseDown, in: parent))
        // A non-clipping NSView can report a nonempty visibleRect entirely
        // outside its bounds. Such a reused/offscreen anchor must not win.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        scroll.documentView = document
        parent.contentView = scroll
        let visibleAnchor = InfoPopoverAnchorView(frame: NSRect(x: 100, y: 40, width: 16, height: 16))
        let offscreenAnchor = InfoPopoverAnchorView(frame: NSRect(x: 100, y: 340, width: 16, height: 16))
        document.addSubview(visibleAnchor)
        document.addSubview(offscreenAnchor)
        scroll.contentView.scroll(to: .zero)
        parent.layoutIfNeeded()
        let presenter = InfoPopoverPresenter()
        let visibleToken = UUID(), offscreenToken = UUID()
        presenter.register(visibleToken, id: "shared", view: visibleAnchor)
        presenter.register(offscreenToken, id: "shared", view: offscreenAnchor)
        precondition(!offscreenAnchor.visibleRect.isEmpty && offscreenAnchor.bounds.intersection(offscreenAnchor.visibleRect).isEmpty,
                     "fixture must expose a nonempty visibleRect outside the anchor bounds")
        presenter.sourceView = scroll
        presenter.select("shared")
        precondition(presenter.state.presented == visibleToken, "an offscreen anchor must not displace the visible button")
        precondition(presenter.attachmentRect == CGRect(x: 100, y: scroll.bounds.height - 56, width: 16, height: 16),
                     "the page attachment must match the button in SwiftUI coordinates")
        visibleAnchor.frame.origin.y = -8
        presenter.select("shared")
        precondition(presenter.state.presented == visibleToken, "partially visible anchors remain eligible for native presentation")
        precondition(presenter.attachmentRect == CGRect(x: 100, y: scroll.bounds.height - 8, width: 16, height: 8),
                     "only the visible button bounds should anchor the popover")
        visibleAnchor.frame.origin.y = -40
        var clearedSelection = false
        presenter.clearSelection = { [weak presenter] in clearedSelection = true; presenter?.select(nil) }
        presenter.select("shared")
        precondition(clearedSelection && presenter.state.presented == nil, "no visible anchor must clear the selection")

        // Deterministic side-fitting fallback for wide anchors (never depends on mouse position).
        let screen1440 = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Normal name/title anchor with ample clearance keeps its full rect.
        let titleRect = CGRect(x: 32, y: 300, width: 140, height: 20)
        let titleScreen = CGRect(x: 32, y: 300, width: 140, height: 20)
        precondition(InfoPopoverPresenter.sideFittingRect(titleRect, screenRect: titleScreen, screenVisible: screen1440) == titleRect,
                     "name anchors with horizontal room beside them must keep their full rect")
        // Extremely wide anchor on a full-width window collapses deterministically to the leading edge.
        let wide = CGRect(x: 32, y: 400, width: 1340, height: 60)
        let wideScreen = CGRect(x: 32, y: 400, width: 1340, height: 60)
        let collapsed = InfoPopoverPresenter.sideFittingRect(wide, screenRect: wideScreen, screenVisible: screen1440)
        precondition(collapsed == CGRect(x: 32, y: 400, width: 1, height: 60),
                     "wide anchor must collapse deterministically to the edge with more horizontal clearance")
        // Tight display (1000 pt wide) nudges deterministically so a side arrow still fits.
        let screen1000 = CGRect(x: 0, y: 0, width: 1000, height: 640)
        let wide1000 = CGRect(x: 32, y: 300, width: 900, height: 60)
        let tight = InfoPopoverPresenter.sideFittingRect(wide1000, screenRect: wide1000, screenVisible: screen1000)
        precondition(tight.width == 1 && (screen1000.maxX - tight.minX) >= InfoPopoverPresenter.requiredSideClearance,
                     "tight display must keep enough horizontal clearance for a side arrow")

        // Live maximized-window check: a tall 460x640 popover on a middle name-anchored row must keep a side arrow
        // pointing at the name on the trailing side (anchorEdge == 0, arrow on popover's left).
        if let visibleScreen = NSScreen.main?.visibleFrame {
            let nameModel = Model()
            let nameHost = NSHostingView(rootView: NameAnchoredRowFixture(model: nameModel))
            window.setFrame(visibleScreen, display: true)
            window.contentView = nameHost
            window.makeKeyAndOrderFront(nil)
            pump()
            nameModel.selected = Item(id: 1)
            pump()
            precondition(nameModel.selected?.id == 1 && popups().count == 1,
                         "name-anchored middle row must present its native popover")
            let frameView = popups()[0].contentView?.superview
            let anchorEdge = frameView?.value(forKey: "anchorEdge") as? UInt
            precondition(anchorEdge == 0 || anchorEdge == 2,
                         "name-anchored middle row popover must keep a side arrow (0=minX or 2=maxX), got \(String(describing: anchorEdge))")
            nameModel.selected = nil
            pump()
            precondition(popups().isEmpty, "name-anchored middle row popover must dismiss cleanly")

            // Header-button capacity popover hosted on the page outside MacReorderableList opens below with a top arrow.
            let headerModel = Model()
            let headerHost = NSHostingView(rootView: HeaderPopoverFixture(model: headerModel))
            window.contentView = headerHost
            window.makeKeyAndOrderFront(nil)
            pump()
            headerModel.selected = Item(id: 99)
            pump()
            precondition(headerModel.selected?.id == 99 && popups().count == 1,
                         "header capacity button must present its page-hosted popover")
            let headerFrameView = popups()[0].contentView?.superview
            let headerAnchorEdge = headerFrameView?.value(forKey: "anchorEdge") as? UInt
            precondition(headerAnchorEdge == 3,
                         "header capacity popover must open below with a top arrow (3=maxY), got \(String(describing: headerAnchorEdge))")
            headerModel.selected = nil
            pump()
            precondition(popups().isEmpty, "header capacity popover must dismiss cleanly")
        }

        window.orderOut(nil)
        print("PASS: rapid A->B->A, pre-readiness cancellation/reopen, exact attachment geometry, shield isolation, clipped-anchor selection, name-anchored side arrow, and page-hosted header popover")
    }
}
