//
//  LiquidGlassDesignSystem.swift
//  wBlock
//
//  Created by Alexander Skula on 10/9/25.
//

import SwiftUI
import wBlockCoreService

extension View {
    @ViewBuilder
    func liquidGlassCompat(
        cornerRadius: CGFloat = 12,
        material: Material = .regularMaterial
    ) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
        #else
        self.background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
        #endif
    }
}

#if os(macOS)
/// Filters and Userscripts share the same toolbar order: search, Add and
/// Update together, pending Apply on its own, then the enabled-only filter.
/// On macOS 26 compact glass groups keep an eight-point gap; older releases
/// retain their flat action group and trailing search field.
///
/// Native list tabs pin the window-toolbar material behind the tab picker.
struct MacActionsToolbar<Primary: View, Apply: View, Filter: View>: ViewModifier {
    @Binding var searchText: String
    @Binding var focusRequest: Bool
    let searchPrompt: LocalizedStringKey
    let hasPendingChanges: Bool
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let apply: () -> Apply
    @ViewBuilder let filter: () -> Filter

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .automatic) { compactActions }
                    .sharedBackgroundVisibility(.hidden)
            }
            .toolbarBackground(.visible, for: .windowToolbar)
        } else {
            content.toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    primary()
                    apply()
                    filter()
                }
                ToolbarItem(placement: .automatic) {
                    ToolbarSearchField(text: $searchText, isExpanded: $focusRequest, prompt: searchPrompt)
                }
            }
        }
    }

    @available(macOS 26.0, *)
    private var compactActions: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 8) {
                // Search lives in the same stack so it keeps the 8pt gap;
                // as a separate toolbar item it butted against Add.
                InlineGlassSearchField(text: $searchText, focusRequest: $focusRequest, prompt: searchPrompt)
                // Buttons that share a capsule get the smaller hit target and
                // hover disc (#771); a button alone in its capsule fills it.
                HStack(spacing: 0) {
                    primary()
                    if !hasPendingChanges { apply() }
                }
                    .environment(\.compactToolbarGrouped, !hasPendingChanges)
                    .frame(height: 36)
                    .glassEffect(.regular.interactive(), in: .capsule)
                if hasPendingChanges {
                    apply()
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                filter()
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CompactToolbarButtonStyle())
    }
}

/// Toolbar for pages pushed inside the navigation stack (Site Settings,
/// Element Zapper, Logs): the action buttons retain their native toolbar
/// grouping; search is supplied separately by `toolbarSearch`.
/// Native action items are used here because a custom multi-button item
/// inside a pushed page reports the first button's accessibility name for
/// every button.
struct MacPushedActionsToolbar<Actions: View>: ViewModifier {
    @ViewBuilder let actions: () -> Actions

    init(@ViewBuilder actions: @escaping () -> Actions) {
        self.actions = actions
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    actions()
                        .labelStyle(.iconOnly)
                        .environment(\.compactToolbarGrouped, true)
                        .buttonStyle(CompactToolbarButtonStyle())
                }
            }
        } else {
            // Keep action items separate on older macOS releases.
            content.toolbar {
                ToolbarItemGroup(placement: .automatic) { actions() }
            }
        }
    }
}

private struct CompactToolbarGroupedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var compactToolbarGrouped: Bool {
        get { self[CompactToolbarGroupedKey.self] }
        set { self[CompactToolbarGroupedKey.self] = newValue }
    }
}

private struct CompactToolbarTextLabelKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var compactToolbarTextLabel: Bool {
        get { self[CompactToolbarTextLabelKey.self] }
        set { self[CompactToolbarTextLabelKey.self] = newValue }
    }
}

@available(macOS 26.0, *)
private struct CompactToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @Environment(\.compactToolbarTextLabel) private var isTextLabel
    @Environment(\.compactToolbarGrouped) private var isGrouped

    private var side: CGFloat { isGrouped ? 30 : 36 }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isTextLabel ? 13 : (isGrouped ? 15 : 17)))
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: isTextLabel ? nil : side, height: side)
            .padding(.horizontal, isTextLabel ? 10 : 0)
            .contentShape(Rectangle())
            .foregroundStyle(.primary)
            .background(Color.primary.opacity(isEnabled ? (configuration.isPressed ? 0.12 : (isHovered ? 0.08 : 0)) : 0), in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
            .onHover { isHovered = $0 }
            .padding(isGrouped ? 3 : 0)
    }
}


/// Compact inline glass search on macOS 26 and the original toolbar field on older systems.
/// Requests are one-shot so menu and notification commands can focus the field repeatedly.
struct ToolbarSearchModifier: ViewModifier {
    @Binding var text: String
    @Binding var focusRequest: Bool
    let prompt: LocalizedStringKey

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .primaryAction) {
                    InlineGlassSearchField(text: $text, focusRequest: $focusRequest, prompt: prompt)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content.toolbar {
                ToolbarItem(placement: .automatic) {
                    ToolbarSearchField(text: $text, isExpanded: $focusRequest, prompt: prompt)
                }
            }
        }
    }
}

extension View {
    #if os(macOS)
    func toolbarSearch(
        text: Binding<String>,
        focusRequest: Binding<Bool>,
        prompt: LocalizedStringKey
    ) -> some View {
        modifier(ToolbarSearchModifier(text: text, focusRequest: focusRequest, prompt: prompt))
    }
    #endif
}

@available(macOS 26.0, *)
struct InlineGlassSearchField: View {
    @Binding var text: String
    @Binding var focusRequest: Bool
    let prompt: LocalizedStringKey

    @State private var isExpanded = false
    @State private var focusRequests = 0
    @State private var isVisible = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Button(action: expandAndFocus) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .fixedSize()
                    .foregroundStyle(text.isEmpty ? Color.primary : Color.accentColor)
                    .contentTransition(.identity)
                    .transaction { transaction in transaction.animation = nil }
                    .frame(width: isExpanded ? 20 : 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(prompt)
            .accessibilityValue(text)
            .help(prompt)

            if isExpanded {
                TextField(prompt, text: $text)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onExitCommand {
                        text = ""
                        collapse()
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .noFocusRingCompat()
                    .help(String(localized: "Clear"))
                    .accessibilityLabel(Text("Clear"))
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, isExpanded ? 8 : 0)
        .frame(minWidth: isExpanded ? 140 : 36, idealWidth: isExpanded ? 180 : 36, maxWidth: isExpanded ? 180 : 36)
        .frame(height: 36)
        .background {
            if isExpanded {
                ToolbarFieldFocuser(request: focusRequests, onClickOutside: {
                    guard isVisible, isExpanded, text.isEmpty else { return }
                    collapse()
                })
                    .frame(height: 36)
            }
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isExpanded)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: text.isEmpty)
        .onAppear {
            isVisible = true
            if !text.isEmpty { isExpanded = true }
            handleFocusRequest()
        }
        .onChangeCompat(of: text) { _, value in
            if !value.isEmpty { isExpanded = true }
        }
        .onChangeCompat(of: focusRequest) { _, requested in
            if requested { handleFocusRequest() }
        }
        .onChangeCompat(of: isFocused) { _, focused in
            if !focused && isVisible && isExpanded && text.isEmpty { collapse() }
        }
        .onDisappear {
            isVisible = false
            collapse()
        }
    }

    private func handleFocusRequest() {
        guard focusRequest, isVisible else { return }
        isExpanded = true
        focusRequests += 1
        focusRequest = false
        DispatchQueue.main.async {
            guard isVisible, isExpanded else { return }
            isFocused = true
        }
    }

    private func expandAndFocus() {
        isExpanded = true
        focusRequests += 1
        DispatchQueue.main.async {
            guard isVisible, isExpanded else { return }
            isFocused = true
        }
    }

    private func collapse() {
        isExpanded = false
        isFocused = false
    }
}

/// A toolbar search field in the shape the HIG expects on the Mac: the
/// magnifier sits inside an always-visible field, with a clear button once
/// there is text. Setting `isExpanded` moves keyboard focus into the field
/// (⌘F); it flips back to false once focus has been requested, so repeated
/// requests keep working.
struct ToolbarSearchField: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    var prompt: LocalizedStringKey = "Search"

    @FocusState private var isFocused: Bool
    @State private var focusRequests = 0
    @State private var usesCompactLayout = false
    @State private var isPopoverPresented = false

    @ViewBuilder
    var body: some View {
        if #available(macOS 13.0, *) {
            ViewThatFits(in: .horizontal) {
                searchField
                    .onAppear { usesCompactLayout = false }
                Button {
                    isExpanded = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 36, height: fieldHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(prompt)
                .help(prompt)
                .onAppear { usesCompactLayout = true }
            }
            .modifier(ToolbarSearchFieldChrome())
            .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                searchField
                    .padding(8)
            }
            .onAppear { if isExpanded { requestFocus() } }
            .onChangeCompat(of: isExpanded) { _, wantsFocus in
                if wantsFocus { requestFocus() }
            }
        } else {
            searchField
                .modifier(ToolbarSearchFieldChrome())
                .onAppear { if isExpanded { requestFocus() } }
                .onChangeCompat(of: isExpanded) { _, wantsFocus in
                    if wantsFocus { requestFocus() }
                }
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand { dismissSearch() }

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .noFocusRingCompat()
                .help(String(localized: "Clear"))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 200, height: fieldHeight)
        .contentShape(Rectangle())
        .background(ToolbarFieldFocuser(request: focusRequests))
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
    }

    private var fieldHeight: CGFloat {
        if #available(macOS 26.0, *) { return 36 }
        return 28
    }

    private func requestFocus() {
        focusRequests += 1
        if usesCompactLayout {
            isPopoverPresented = true
        }
        DispatchQueue.main.async { isExpanded = false }
    }

    private func dismissSearch() {
        text = ""
        isFocused = false
        isPopoverPresented = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

/// The glass effect is applied to the field itself rather than to a shape in
/// its background. A glass shape placed in `.background` renders above the
/// field's text on macOS 26, hiding what the user types.
private struct ToolbarSearchFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            )
        }
    }
}

/// Toolbar items live in AppKit's toolbar view hierarchy, where SwiftUI's
/// `@FocusState` does not reliably move the caret (#613). Each new focus
/// request makes the sibling NSTextField the first responder directly.
private struct ToolbarFieldFocuser: NSViewRepresentable {
    let request: Int
    let onClickOutside: (() -> Void)?

    init(request: Int, onClickOutside: (() -> Void)? = nil) {
        self.request = request
        self.onClickOutside = onClickOutside
    }

    final class Coordinator {
        var handledRequest = 0
        var pendingFocus: DispatchWorkItem?
        var eventMonitor: Any?
        var pendingOutsideClick: DispatchWorkItem?
        var onClickOutside: (() -> Void)?

        func installMouseMonitor(for view: NSView) {
            guard onClickOutside != nil, eventMonitor == nil else { return }
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak view, weak self] event in
                guard let view, let self else { return event }
                guard self.isOutside(event, view: view) else {
                    self.pendingOutsideClick?.cancel()
                    self.pendingOutsideClick = nil
                    return event
                }

                if event.type == .leftMouseDown {
                    // A blank click can omit mouseUp when the toolbar resizes;
                    // keep a deferred fallback, but give normal controls time
                    // to receive their mouseUp first.
                    self.pendingOutsideClick?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        self?.onClickOutside?()
                        self?.pendingOutsideClick = nil
                    }
                    self.pendingOutsideClick = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: work)
                } else {
                    self.pendingOutsideClick?.cancel()
                    self.pendingOutsideClick = nil
                    // Let the clicked control finish its action before the toolbar resizes.
                    DispatchQueue.main.async { [weak self] in
                        self?.onClickOutside?()
                    }
                }
                return event
            }
        }

        private func isOutside(_ event: NSEvent, view: NSView) -> Bool {
            guard let window = view.window else { return false }
            let pointInWindow: NSPoint
            if let eventWindow = event.window {
                guard eventWindow === window || event.windowNumber == window.windowNumber else { return false }
                pointInWindow = event.locationInWindow
            } else {
                // Nil-window events are only trusted while this window is active,
                // and their location is interpreted in screen coordinates.
                guard window.isKeyWindow || window.isMainWindow,
                      window.frame.contains(event.locationInWindow) else { return false }
                pointInWindow = window.convertPoint(fromScreen: event.locationInWindow)
            }
            return !view.bounds.contains(view.convert(pointInWindow, from: nil))
        }

        func cancelPendingFocus() {
            pendingFocus?.cancel()
            pendingFocus = nil
        }

        func cancel() {
            cancelPendingFocus()
            pendingOutsideClick?.cancel()
            pendingOutsideClick = nil
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            onClickOutside = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.onClickOutside = onClickOutside
        context.coordinator.installMouseMonitor(for: view)
        if request > 0 {
            context.coordinator.handledRequest = request
            focusSibling(of: view, coordinator: context.coordinator, attemptsLeft: 10)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onClickOutside = onClickOutside
        context.coordinator.installMouseMonitor(for: nsView)
        guard request != context.coordinator.handledRequest else { return }
        context.coordinator.handledRequest = request
        focusSibling(of: nsView, coordinator: context.coordinator, attemptsLeft: 10)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    private func focusSibling(of view: NSView, coordinator: Coordinator, attemptsLeft: Int) {
        coordinator.cancelPendingFocus()
        let work = DispatchWorkItem { [weak view, weak coordinator] in
            guard let view, let coordinator,
                  coordinator.pendingFocus?.isCancelled == false else { return }
            guard let window = view.window else {
                if attemptsLeft > 0 {
                    self.focusSibling(of: view, coordinator: coordinator, attemptsLeft: attemptsLeft - 1)
                }
                return
            }
            guard window.isVisible, !view.isHiddenOrHasHiddenAncestor else { return }
            if let field = Self.textField(near: view) {
                window.makeFirstResponder(field)
            } else if attemptsLeft > 0 {
                self.focusSibling(of: view, coordinator: coordinator, attemptsLeft: attemptsLeft - 1)
            }
        }
        coordinator.pendingFocus = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(60), execute: work)
    }

    private static func textField(near view: NSView) -> NSTextField? {
        var ancestor = view.superview
        while let current = ancestor {
            if let field = editableTextField(in: current) { return field }
            ancestor = current.superview
        }
        return nil
    }

    private static func editableTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let field = editableTextField(in: subview) { return field }
        }
        return nil
    }
}

#endif
