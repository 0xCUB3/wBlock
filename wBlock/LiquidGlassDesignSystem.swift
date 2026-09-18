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
/// The Filters and Userscripts tabs share one macOS toolbar shape: Add and
/// Update together, pending Apply on its own, then the enabled-only filter and
/// a persistent search field. On macOS 26 compact glass groups keep an
/// eight-point gap; older releases render the same buttons as one flat group.
struct MacActionsToolbar<Primary: View, Apply: View, Filter: View, Search: View>: ViewModifier {
    let hasPendingChanges: Bool
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let apply: () -> Apply
    @ViewBuilder let filter: () -> Filter
    @ViewBuilder let search: () -> Search

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .automatic) { compactActions }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content.toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    primary()
                    apply()
                    filter()
                }
                ToolbarItem(placement: .automatic) { search() }
            }
        }
    }

    @available(macOS 26.0, *)
    private var compactActions: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 8) {
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
                search()
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CompactToolbarButtonStyle())
    }
}

/// Toolbar for pages pushed inside the navigation stack (Site Settings,
/// Element Zapper, Logs): the action buttons share one native glass group
/// with compact hit targets; the search field supplies its own capsule.
/// Native action items are used here because a custom multi-button item
/// inside a pushed page reports the first button's accessibility name for
/// every button.
struct MacPushedActionsToolbar<Actions: View, Search: View>: ViewModifier {
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let search: () -> Search

    init(
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder search: @escaping () -> Search = { EmptyView() }
    ) {
        self.actions = actions
        self.search = search
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
                if Search.self != EmptyView.self {
                    ToolbarItem(placement: .automatic) { search() }
                        .sharedBackgroundVisibility(.hidden)
                }
            }
        } else {
            // ToolbarContentBuilder has no `if` before macOS 13; an EmptyView
            // search item takes no space.
            content.toolbar {
                ToolbarItemGroup(placement: .automatic) { actions() }
                ToolbarItem(placement: .automatic) { search() }
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

    var body: some View {
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
        .modifier(ToolbarSearchFieldChrome())
        .background(ToolbarFieldFocuser(request: focusRequests))
        .animation(.easeOut(duration: 0.15), value: text.isEmpty)
        .onAppear { if isExpanded { requestFocus() } }
        .onChangeCompat(of: isExpanded) { _, wantsFocus in
            if wantsFocus { requestFocus() }
        }
    }

    private var fieldHeight: CGFloat {
        if #available(macOS 26.0, *) { return 36 }
        return 28
    }

    private func requestFocus() {
        focusRequests += 1
        DispatchQueue.main.async { isExpanded = false }
    }

    private func dismissSearch() {
        text = ""
        isFocused = false
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

    final class Coordinator {
        var handledRequest = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        if request > 0 {
            context.coordinator.handledRequest = request
            focusSibling(of: view, attemptsLeft: 10)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard request != context.coordinator.handledRequest else { return }
        context.coordinator.handledRequest = request
        focusSibling(of: nsView, attemptsLeft: 10)
    }

    private func focusSibling(of view: NSView, attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(60)) {
            if let window = view.window, let field = Self.textField(near: view) {
                window.makeFirstResponder(field)
            } else if attemptsLeft > 0 {
                focusSibling(of: view, attemptsLeft: attemptsLeft - 1)
            }
        }
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
