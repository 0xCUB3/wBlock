import SwiftUI

private struct InfoPopoverAnchors: PreferenceKey {
    static var defaultValue: [AnyHashable: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [AnyHashable: Anchor<CGRect>], nextValue: () -> [AnyHashable: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    @ViewBuilder
    func infoPopoverAnchor(_ id: AnyHashable?) -> some View {
        #if os(macOS)
        if let id {
            anchorPreference(key: InfoPopoverAnchors.self, value: .bounds) { [id: $0] }
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
        overlayPreferenceValue(InfoPopoverAnchors.self) { anchors in
            InfoPopoverHost(item: item, anchors: anchors, onDismiss: onDismiss, content: content)
        }
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

private struct InfoPopoverHost<Item: Identifiable, Info: View>: View {
    @Binding var item: Item?
    let anchors: [AnyHashable: Anchor<CGRect>]
    let onDismiss: () -> Void
    let content: (Item) -> Info
    @State private var hostIsReady = false

    var body: some View {
        GeometryReader { geometry in
            if let selected = item, let anchor = anchors[AnyHashable(selected.id)] {
                let rect = geometry[anchor]
                if rect.width > 0, rect.height > 0 {
                    let selectedID = selected.id
                    let presented = Binding<Item?>(
                        get: { hostIsReady ? item : nil },
                        set: { value in
                            guard item?.id == selectedID else { return }
                            item = value
                        }
                    )
                    // Keep one host when changing items, and wait for its actual
                    // AppKit layout before presenting from the button-sized bounds.
                    Color.clear.frame(width: rect.width, height: rect.height)
                        .background(InfoPopoverLayoutObserver { hostIsReady = true })
                        .background(PopoverWindowShield { presented.wrappedValue = nil })
                        .popover(item: presented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) { value in
                            content(value).onDisappear(perform: onDismiss)
                        }
                        .position(x: rect.midX, y: rect.midY)
                        .onDisappear { hostIsReady = false }
                }
            }
        }
    }
}

private struct InfoPopoverLayoutObserver: NSViewRepresentable {
    let onReady: () -> Void

    func makeNSView(context: Context) -> InfoPopoverAnchorView { InfoPopoverAnchorView() }
    func updateNSView(_ view: InfoPopoverAnchorView, context: Context) {
        view.onReady = onReady
        view.needsLayout = true
    }
}

private final class InfoPopoverAnchorView: NSView {
    var onReady: () -> Void = {}
    private var reported = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reported = false
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard window != nil, !bounds.isEmpty, !reported else { return }
        reported = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, !self.bounds.isEmpty else { return }
            self.onReady()
        }
    }
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
