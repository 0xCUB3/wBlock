import SwiftUI

extension View {
    @ViewBuilder
    func infoPopoverAnchor(_ id: AnyHashable?) -> some View {
        #if os(macOS)
        if let id {
            background(InfoPopoverSlots(id: id))
        } else { self }
        #else
        self
        #endif
    }

    @ViewBuilder
    func infoPresentation<Item: Identifiable, Info: View>(
        item: Binding<Item?>,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Item) -> Info
    ) -> some View {
        #if os(macOS)
        modifier(InfoPresentationModifier(item: item, onDismiss: onDismiss, info: content))
        #else
        sheet(item: item, onDismiss: onDismiss, content: content)
        #endif
    }

    @ViewBuilder
    func modalPopover<Content: View>(
        isPresented: Binding<Bool>, arrowEdge: Edge,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        background {
            if isPresented.wrappedValue { PopoverWindowShield { isPresented.wrappedValue = false } }
        }
        .popover(isPresented: isPresented, arrowEdge: arrowEdge, content: content)
        #else
        popover(isPresented: isPresented, arrowEdge: arrowEdge, content: content)
        #endif
    }
}

#if os(macOS)
import AppKit

/// Which info anchor shows its popover. Tokens name one anchor view, not an
/// item: the same list can sit in two regional groups, and each row must
/// present from its own button.
struct InfoPopoverState: Equatable {
    struct Anchor {
        let token: UUID
        let id: AnyHashable
        let windowNumber: Int
        let frame: CGRect
    }
    private struct ClosingClick: Equatable { let token: UUID; let eventNumber: Int }

    private(set) var presented: UUID?
    private var closingClick: ClosingClick?

    /// The clicked anchor wins; without a click (a menu or keyboard) the topmost does.
    static func anchor(for id: AnyHashable, in anchors: [Anchor],
                       click: (windowNumber: Int, point: CGPoint)?) -> UUID? {
        let matches = anchors.filter { $0.id == id }
        if let click, let hit = matches.first(where: { $0.windowNumber == click.windowNumber && $0.frame.contains(click.point) }) {
            return hit.token
        }
        return matches.max { $0.frame.maxY < $1.frame.maxY }?.token
    }

    /// False when this is the mouse-up of the click that just closed the same
    /// anchor: clicking an open info button closes it rather than reopening
    /// into a popover that is still animating away.
    mutating func request(_ token: UUID, mouseUp eventNumber: Int?) -> Bool {
        defer { closingClick = nil }
        if let eventNumber, closingClick == ClosingClick(token: token, eventNumber: eventNumber) { return false }
        presented = token
        return true
    }

    /// False for a late dismissal of an anchor that is no longer presented.
    mutating func dismiss(_ token: UUID, mouseDown eventNumber: Int?) -> Bool {
        guard presented == token else { return false }
        presented = nil
        closingClick = eventNumber.map { ClosingClick(token: token, eventNumber: $0) }
        return true
    }

    mutating func clear() { presented = nil }
}

@MainActor
final class InfoPopoverPresenter: ObservableObject {
    @Published private(set) var state = InfoPopoverState()
    var clearSelection: () -> Void = {}
    var lastItem: Any?
    private var anchors: [UUID: (id: AnyHashable, view: InfoPopoverAnchorView)] = [:]

    func register(_ token: UUID, id: AnyHashable, view: InfoPopoverAnchorView) { anchors[token] = (id, view) }
    func unregister(_ token: UUID) {
        guard let id = anchors.removeValue(forKey: token)?.id else { return }
        // A presented row that moves (a category change from its own popover)
        // follows its new anchor; one that leaves the list closes its popover.
        DispatchQueue.main.async { [self] in
            guard anchors[token] == nil, state.presented == token else { return }
            if let moved = anchors.first(where: { $0.value.id == id && $0.value.view.window != nil })?.key {
                _ = state.request(moved, mouseUp: nil)
            } else {
                state.clear()
                clearSelection()
            }
        }
    }

    func select(_ id: AnyHashable?) {
        guard let id else { state.clear(); return }
        let event = NSApp.currentEvent
        let isMouse = event.map { [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp].contains($0.type) } ?? false
        let click = isMouse ? event.flatMap { event in event.window.map { ($0.windowNumber, event.locationInWindow) } } : nil
        let visible = anchors.compactMap { token, anchor -> InfoPopoverState.Anchor? in
            let view = anchor.view
            guard anchor.id == id, let window = view.window, !view.isHiddenOrHasHiddenAncestor,
                  !view.visibleRect.isEmpty else { return nil }
            return .init(token: token, id: anchor.id, windowNumber: window.windowNumber, frame: view.convert(view.bounds, to: nil))
        }
        let mouseUp = event?.type == .leftMouseUp ? event?.eventNumber : nil
        // An item with no visible anchor, or a closing click, must not leave
        // a selection behind that no popover shows.
        guard let token = InfoPopoverState.anchor(for: id, in: visible, click: click),
              state.request(token, mouseUp: mouseUp) else { return clearSelection() }
    }

    func dismiss(_ token: UUID) {
        let event = NSApp.currentEvent
        guard state.dismiss(token, mouseDown: event?.type == .leftMouseDown ? event?.eventNumber : nil) else { return }
        clearSelection()
    }
}

private struct InfoPopoverEntry {
    let presenter: InfoPopoverPresenter
    let content: () -> AnyView
}

private struct InfoPopoverEntriesKey: EnvironmentKey {
    static var defaultValue: [InfoPopoverEntry] { [] }
}

private extension EnvironmentValues {
    /// Native list rows host SwiftUI in their own NSHostingViews and receive
    /// the environment explicitly; preferences never reach the presenter.
    var infoPopoverEntries: [InfoPopoverEntry] {
        get { self[InfoPopoverEntriesKey.self] }
        set { self[InfoPopoverEntriesKey.self] = newValue }
    }
}

private struct InfoPresentationModifier<Item: Identifiable, Info: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: () -> Void
    let info: (Item) -> Info
    @StateObject private var presenter = InfoPopoverPresenter()
    @Environment(\.infoPopoverEntries) private var entries

    func body(content: Content) -> some View {
        let selection = $item
        presenter.clearSelection = { selection.wrappedValue = nil }
        if let item { presenter.lastItem = item }
        // Keep the closing popover's content until it finishes animating away.
        let shown = item ?? presenter.lastItem as? Item
        let entry = InfoPopoverEntry(presenter: presenter) { [info, onDismiss] in
            shown.map { AnyView(info($0).onDisappear(perform: onDismiss)) } ?? AnyView(EmptyView())
        }
        let id = item.map { AnyHashable($0.id) }
        let scoped = content.environment(\.infoPopoverEntries, entries + [entry])
        if #available(macOS 14.0, *) {
            return AnyView(scoped.onChange(of: id) { presenter.select($1) })
        } else {
            return AnyView(scoped.onChange(of: id, perform: presenter.select))
        }
    }
}

private struct InfoPopoverSlots: View {
    let id: AnyHashable
    @Environment(\.infoPopoverEntries) private var entries

    var body: some View {
        ZStack {
            ForEach(entries.indices, id: \.self) { index in
                InfoPopoverSlot(id: id, presenter: entries[index].presenter, content: entries[index].content)
            }
        }
    }
}

private struct InfoPopoverSlot: View {
    let id: AnyHashable
    @ObservedObject var presenter: InfoPopoverPresenter
    let content: () -> AnyView
    @State private var token = UUID()

    var body: some View {
        let isPresented = Binding(
            get: { presenter.state.presented == token },
            set: { if !$0 { presenter.dismiss(token) } }
        )
        InfoPopoverAnchorRegistration(token: token, id: id, presenter: presenter)
            .background {
                if isPresented.wrappedValue { PopoverWindowShield { presenter.dismiss(token) } }
            }
            .popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .top, content: content)
    }
}

private struct InfoPopoverAnchorRegistration: NSViewRepresentable {
    let token: UUID
    let id: AnyHashable
    let presenter: InfoPopoverPresenter

    func makeNSView(context: Context) -> InfoPopoverAnchorView { InfoPopoverAnchorView() }
    func updateNSView(_ view: InfoPopoverAnchorView, context: Context) {
        view.registration = (token, id, presenter)
    }
    static func dismantleNSView(_ view: InfoPopoverAnchorView, coordinator: ()) { view.registration = nil }
}

final class InfoPopoverAnchorView: NSView {
    fileprivate var registration: (token: UUID, id: AnyHashable, presenter: InfoPopoverPresenter)? {
        didSet {
            if let oldValue, oldValue.token != registration?.token || oldValue.presenter !== registration?.presenter {
                oldValue.presenter.unregister(oldValue.token)
            }
            register()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        register()
    }

    // Off-window views are measuring sizers or reusable outline cells.
    private func register() {
        guard let registration else { return }
        if window == nil {
            registration.presenter.unregister(registration.token)
        } else {
            registration.presenter.register(registration.token, id: registration.id, view: self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct PopoverWindowShield: NSViewRepresentable {
    let dismiss: () -> Void
    func makeNSView(context: Context) -> PopoverWindowShieldView { PopoverWindowShieldView() }
    func updateNSView(_ view: PopoverWindowShieldView, context: Context) { view.dismiss = dismiss }
    static func dismantleNSView(_ view: PopoverWindowShieldView, coordinator: ()) { view.stopMonitoring() }
}

final class PopoverWindowShieldView: NSView {
    var dismiss: () -> Void = {}
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            self?.consume(event.type, in: event.window) == true ? nil : event
        }
    }

    // Only the presenting window is blocked. Popover controls, menus, and sheets
    // have their own windows and must retain normal mouse and scroll handling.
    func consume(_ type: NSEvent.EventType, in eventWindow: NSWindow?) -> Bool {
        guard let window, eventWindow === window else { return false }
        switch type {
        case .scrollWheel: return true
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            dismiss()
            return false
        default: return false
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
    deinit { stopMonitoring() }
}
#endif
