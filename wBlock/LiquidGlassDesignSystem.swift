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
/// Apply together, the enabled-only filter on its own, then search. On macOS 26
/// compact glass groups keep an eight-point gap; older releases render the
/// same buttons as one flat group.
struct MacActionsToolbar<Primary: View, Filter: View, Search: View>: ViewModifier {
    let isSearchExpanded: Bool
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let filter: () -> Filter
    @ViewBuilder let search: () -> Search

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbar {
                if isSearchExpanded {
                    ToolbarItem(placement: .automatic) { search() }
                } else {
                    ToolbarItem(placement: .automatic) { compactActions }
                        .sharedBackgroundVisibility(.hidden)
                }
            }
        } else {
            content.toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    if !isSearchExpanded {
                        primary()
                        filter()
                    }
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
                HStack(spacing: 0) { primary() }
                    .environment(\.compactToolbarGrouped, true)
                    .padding(.horizontal, 3)
                    .frame(height: 36)
                    .glassEffect(.regular.interactive(), in: .capsule)
                filter()
                    .glassEffect(.regular.interactive(), in: .capsule)
                search()
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(CompactToolbarButtonStyle())
    }
}

/// Toolbar for pages pushed inside the navigation stack (Site Settings,
/// Element Zapper, Logs): the action buttons share one native glass group
/// with compact hit targets, a fixed spacer breaks the bubble, and search
/// stands alone on the right (#771). Native items are used here because a
/// custom multi-button item inside a pushed page reports the first button's
/// accessibility name for every button.
struct MacPushedActionsToolbar<Actions: View, Search: View>: ViewModifier {
    var isSearchExpanded = false
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let search: () -> Search

    init(
        isSearchExpanded: Bool = false,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder search: @escaping () -> Search = { EmptyView() }
    ) {
        self.isSearchExpanded = isSearchExpanded
        self.actions = actions
        self.search = search
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.toolbar {
                if !isSearchExpanded {
                    ToolbarItemGroup(placement: .automatic) {
                        actions().labelStyle(.iconOnly)
                    }
                }
                if Search.self != EmptyView.self {
                    if !isSearchExpanded {
                        ToolbarSpacer(.fixed, placement: .automatic)
                    }
                    ToolbarItem(placement: .automatic) { search() }
                }
            }
        } else {
            content.toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    if !isSearchExpanded { actions() }
                }
                if Search.self != EmptyView.self {
                    ToolbarItem(placement: .automatic) { search() }
                }
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
    }
}

struct ToolbarSearchField: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    var prompt: LocalizedStringKey = "Search"

    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isExpanded {
                HStack(spacing: 6) {
                    TextField(prompt, text: $text)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onExitCommand { collapse() }

                    Button { collapse() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .noFocusRingCompat()
                    .help(String(localized: "Close search"))
                }
                .padding(.horizontal, 8)
                .frame(width: 180)
                .background(ToolbarFieldFocuser())
                .transition(.blurReplaceCompat)
            } else {
                Button {
                    isExpanded = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .transition(.blurReplaceCompat)
            }
        }
        .animation(.smooth(duration: 0.3), value: isExpanded)
        .onChangeCompat(of: isFocused) { _, focused in
            if !focused && isExpanded {
                collapse()
            }
        }
    }

    private func collapse() {
        text = ""
        isExpanded = false
    }
}

/// Toolbar items live in AppKit's toolbar view hierarchy, where SwiftUI's
/// `@FocusState` does not reliably move the caret (#613). Once the expanded
/// field is in a window, make its NSTextField the first responder directly.
private struct ToolbarFieldFocuser: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        focusSibling(of: view, attemptsLeft: 10)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

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
