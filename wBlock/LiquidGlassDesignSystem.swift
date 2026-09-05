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
                HStack(spacing: 0) { primary() }
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

@available(macOS 26.0, *)
private struct CompactToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17))
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .foregroundStyle(.primary)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
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
