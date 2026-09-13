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
            GeometryReader { geometry in
                if let selected = item.wrappedValue, let anchor = anchors[AnyHashable(selected.id)] {
                    Color.clear.frame(width: 1, height: 1)
                        .background(PopoverWindowShield { item.wrappedValue = nil })
                        .popover(item: item, attachmentAnchor: .point(.center), arrowEdge: .top) { value in
                            content(value).onDisappear(perform: onDismiss)
                        }
                        .position(x: geometry[anchor].midX, y: geometry[anchor].midY)
                }
            }
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
            return true
        default: return false
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
    deinit { stopMonitoring() }
}
#endif
