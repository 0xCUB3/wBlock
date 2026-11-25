import SwiftUI

/// On macOS, info opens in a popover, so its action sheets must come from the
/// window. On iOS info is already a sheet and presents its own.
func macOSWindowAction<Action>(_ route: @escaping (Action) -> Void) -> ((Action) -> Void)? {
    #if os(macOS)
    route
    #else
    nil
    #endif
}

extension View {
    @ViewBuilder
    func infoPopoverAnchor(_ id: AnyHashable?, capturesClicks: Bool = true) -> some View {
        #if os(macOS)
        if let id { modifier(InfoPopoverAnchor(id: id, capturesClicks: capturesClicks)) } else { self }
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
    private struct Click: Equatable { let token: UUID; let id: AnyHashable }

    private(set) var presented: UUID?
    private var closingClick: ClosingClick?
    private var click: Click?

    /// Records the info button the user just clicked. SwiftUI may report the
    /// selection after the event has passed, so the anchor is named here.
    mutating func clicked(_ token: UUID, id: AnyHashable) { click = Click(token: token, id: id) }

    /// The next selection consumes the click: the clicked anchor wins when it
    /// shows this item; otherwise (a menu or keyboard) the topmost does.
    mutating func anchor(for id: AnyHashable, in anchors: [Anchor], fromKeyboard: Bool = false) -> UUID? {
        defer { click = nil }
        let matches = anchors.filter { $0.id == id }
        if !fromKeyboard, let click, click.id == id, matches.contains(where: { $0.token == click.token }) {
            return click.token
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

    mutating func clear() { presented = nil; click = nil }
}

@MainActor
final class InfoPopoverPresenter: ObservableObject {
    @Published private(set) var state = InfoPopoverState()
    var clearSelection: () -> Void = {}
    var lastItem: Any?
    weak var sourceView: NSView?

    /// Minimum horizontal clearance beside the anchor so macOS keeps the info
    /// popover's side arrow (460 pt content + 26 pt popover chrome + margin).
    nonisolated static let requiredSideClearance: CGFloat = 504

    /// Keeps the full anchor rect when either horizontal side fits on screen.
    /// Otherwise collapses horizontally to a 1 pt slice (preferring the click X)
    /// so NSPopover always has room for a side arrow instead of dropping it when
    /// a wide row sits near the vertical middle of the screen.
    static func sideFittingRect(
        _ rect: CGRect,
        screenRect: CGRect,
        screenVisible: CGRect,
        clickScreenX: CGFloat? = nil,
        requiredClearance: CGFloat = requiredSideClearance
    ) -> CGRect {
        guard rect.width > 1, !screenVisible.isEmpty else { return rect }
        let leftSpace = screenRect.minX - screenVisible.minX
        let rightSpace = screenVisible.maxX - screenRect.maxX
        if max(leftSpace, rightSpace) >= requiredClearance {
            return rect
        }

        var targetScreenX: CGFloat
        if let clickScreenX {
            targetScreenX = min(max(clickScreenX, screenRect.minX), screenRect.maxX)
        } else {
            let leftOfTrailing = screenRect.maxX - screenVisible.minX
            let rightOfLeading = screenVisible.maxX - screenRect.minX
            targetScreenX = leftOfTrailing >= rightOfLeading ? screenRect.maxX : screenRect.minX
        }

        let leftAtTarget = targetScreenX - screenVisible.minX
        let rightAtTarget = screenVisible.maxX - targetScreenX
        if max(leftAtTarget, rightAtTarget) < requiredClearance {
            if leftAtTarget <= rightAtTarget {
                targetScreenX = max(screenRect.minX, screenVisible.maxX - requiredClearance)
            } else {
                targetScreenX = min(screenRect.maxX, screenVisible.minX + requiredClearance)
            }
        }

        let offset = min(max(targetScreenX - screenRect.minX, 0), max(0, rect.width - 1))
        return CGRect(x: rect.minX + offset, y: rect.minY, width: 1, height: rect.height)
    }

    var attachmentRect: CGRect {
        guard let token = state.presented, let view = anchors[token]?.view, let sourceView,
              let window = view.window, sourceView.window === window else { return .zero }
        let visible = view.bounds.intersection(view.visibleRect)
        guard !visible.isEmpty else { return .zero }
        let rect = sourceView.convert(visible, from: view)
        let swiftUIRect = CGRect(
            x: rect.minX - sourceView.bounds.minX,
            y: sourceView.isFlipped ? rect.minY - sourceView.bounds.minY : sourceView.bounds.maxY - rect.maxY,
            width: rect.width, height: rect.height
        )
        guard let screenVisible = window.screen?.visibleFrame else { return swiftUIRect }
        let screenRect = window.convertToScreen(view.convert(visible, to: nil))
        let clickScreenX: CGFloat?
        if let click = presentedClick, click.token == token {
            let clampedX = min(max(click.localX, visible.minX), visible.maxX)
            let windowPoint = view.convert(NSPoint(x: clampedX, y: visible.midY), to: nil)
            clickScreenX = window.convertPoint(toScreen: windowPoint).x
        } else {
            clickScreenX = nil
        }
        return Self.sideFittingRect(
            swiftUIRect,
            screenRect: screenRect,
            screenVisible: screenVisible,
            clickScreenX: clickScreenX
        )
    }

    private var anchors: [UUID: (id: AnyHashable, view: InfoPopoverAnchorView)] = [:]
    private var pendingClick: (token: UUID, localX: CGFloat)?
    private var presentedClick: (token: UUID, localX: CGFloat)?

    private func localClickX(in view: InfoPopoverAnchorView, from event: NSEvent?, allowPointerFallback: Bool) -> CGFloat? {
        guard let window = view.window else { return nil }
        let visible = view.bounds.intersection(view.visibleRect)
        guard !visible.isEmpty else { return nil }
        let windowPoint: NSPoint?
        if let event, event.windowNumber == window.windowNumber,
           event.type == .leftMouseUp || event.type == .leftMouseDown {
            windowPoint = event.locationInWindow
        } else if allowPointerFallback {
            windowPoint = window.mouseLocationOutsideOfEventStream
        } else {
            windowPoint = nil
        }
        guard let windowPoint else { return nil }
        let local = view.convert(windowPoint, from: nil)
        return visible.contains(local) ? local.x : nil
    }

    func register(_ token: UUID, id: AnyHashable, view: InfoPopoverAnchorView) { anchors[token] = (id, view) }
    /// SwiftUI can host a second, window-less copy of an anchor with the same
    /// token while it rebuilds a row. Only the view that owns the registration
    /// may remove it, or the copy evicts the live button and its popover is
    /// cleared before it opens (#931).
    func unregister(_ token: UUID, view: InfoPopoverAnchorView) {
        guard anchors[token]?.view === view, let id = anchors.removeValue(forKey: token)?.id else { return }
        if pendingClick?.token == token { pendingClick = nil }
        // A presented row that moves (a category change from its own popover)
        // follows its new anchor; one that leaves the list closes its popover.
        DispatchQueue.main.async { [self] in
            guard anchors[token] == nil, state.presented == token else { return }
            if presentedClick?.token == token { presentedClick = nil }
            if let moved = anchors.first(where: { $0.value.id == id && $0.value.view.window != nil })?.key {
                _ = state.request(moved, mouseUp: nil)
            } else {
                state.clear()
                clearSelection()
            }
        }
    }

    func select(_ id: AnyHashable?) {
        let click = pendingClick
        pendingClick = nil
        guard let id else {
            presentedClick = nil
            state.clear()
            return
        }
        let event = NSApp.currentEvent
        let visible = anchors.compactMap { token, anchor -> InfoPopoverState.Anchor? in
            let view = anchor.view
            guard anchor.id == id, let window = view.window, !view.isHiddenOrHasHiddenAncestor,
                  !view.bounds.intersection(view.visibleRect).isEmpty else { return nil }
            return .init(token: token, id: anchor.id, windowNumber: window.windowNumber, frame: view.convert(view.bounds, to: nil))
        }
        let mouseUp = event?.type == .leftMouseUp ? event?.eventNumber : nil
        if let event, event.type == .leftMouseUp || event.type == .leftMouseDown,
           let hit = visible.first(where: { $0.windowNumber == event.windowNumber && $0.frame.contains(event.locationInWindow) }) {
            state.clicked(hit.token, id: id)
        }
        let fromKeyboard = event?.type == .keyDown
        // An item with no visible anchor, or a closing click, must not leave
        // a selection behind that no popover shows.
        guard let token = state.anchor(for: id, in: visible, fromKeyboard: fromKeyboard),
              state.request(token, mouseUp: mouseUp) else {
            presentedClick = nil
            return clearSelection()
        }
        if !fromKeyboard,
           let localX = (click?.token == token ? click?.localX : nil)
            ?? anchors[token].flatMap({ localClickX(in: $0.view, from: event, allowPointerFallback: true) }) {
            presentedClick = (token, localX)
        } else {
            presentedClick = nil
        }
    }

    func clicked(_ token: UUID, id: AnyHashable) {
        state.clicked(token, id: id)
        if let view = anchors[token]?.view,
           let localX = localClickX(in: view, from: NSApp.currentEvent, allowPointerFallback: true) {
            pendingClick = (token, localX)
        } else {
            pendingClick = nil
        }
    }

    func dismiss(_ token: UUID) {
        let event = NSApp.currentEvent
        guard state.dismiss(token, mouseDown: event?.type == .leftMouseDown ? event?.eventNumber : nil) else { return }
        presentedClick = nil
        clearSelection()
    }
}

private struct InfoPopoverEntriesKey: EnvironmentKey {
    static var defaultValue: [InfoPopoverPresenter] { [] }
}

private extension EnvironmentValues {
    /// Native list rows host SwiftUI in their own NSHostingViews and receive
    /// the environment explicitly; preferences never reach the presenter.
    var infoPopoverEntries: [InfoPopoverPresenter] {
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
        let id = item.map { AnyHashable($0.id) }
        let token = presenter.state.presented
        let isPresented = Binding(
            get: { presenter.state.presented != nil },
            set: { if !$0, let token { presenter.dismiss(token) } }
        )
        let scoped = content.environment(\.infoPopoverEntries, entries + [presenter])
            .background(InfoPopoverSource(presenter: presenter))
            .background {
                if let token { PopoverWindowShield { presenter.dismiss(token) } }
            }
            .popover(isPresented: isPresented, attachmentAnchor: .rect(.rect(presenter.attachmentRect)), arrowEdge: .leading) {
                if let shown { info(shown).id(shown.id).font(.body).onDisappear(perform: onDismiss) }
            }
        if #available(macOS 14.0, *) {
            return AnyView(scoped.onChange(of: id) { presenter.select($1) })
        } else {
            return AnyView(scoped.onChange(of: id, perform: presenter.select))
        }
    }
}

/// One info anchor. When `capturesClicks` is true (button anchors), its tap
/// names this anchor before the button's action changes selection. Row anchors
/// inside draggable AppKit lists leave `capturesClicks` false so they do not
/// steal mouseDown from NSOutlineView drags; `select(_:)` matches them by click
/// location instead.
private struct InfoPopoverAnchor: ViewModifier {
    let id: AnyHashable
    let capturesClicks: Bool
    @State private var token = UUID()
    @Environment(\.infoPopoverEntries) private var entries

    func body(content: Content) -> some View {
        let anchored = content.background {
            ZStack {
                ForEach(entries.indices, id: \.self) { index in
                    InfoPopoverAnchorRegistration(token: token, id: id, presenter: entries[index])
                }
            }
        }
        if capturesClicks {
            anchored.simultaneousGesture(TapGesture().onEnded {
                for presenter in entries { presenter.clicked(token, id: id) }
            })
        } else {
            anchored
        }
    }
}

/// Host the native popover on the unclipped page, not inside a reusable row.
/// Its attachment rectangle still follows the visible part of the info button.
private struct InfoPopoverSource: NSViewRepresentable {
    let presenter: InfoPopoverPresenter
    func makeNSView(context: Context) -> NSView {
        let view = InfoPopoverAnchorView()
        presenter.sourceView = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { presenter.sourceView = view }
    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        // Keep weak reference clean on teardown; SwiftUI drops the view shortly after.
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
                oldValue.presenter.unregister(oldValue.token, view: self)
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
            registration.presenter.unregister(registration.token, view: self)
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
