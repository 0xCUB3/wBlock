//
//  LiquidGlassDesignSystem.swift
//  wBlock
//
//  Created by Alexander Skula on 10/9/25.
//

import SwiftUI

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

/// On macOS 26 and later every item is a system toolbar item with the system's
/// own sizing; search is the native toolbar search field.
/// On iOS and iPadOS, Update/Apply sits alone at the leading edge. That is a
/// settled decision: do not regroup it with the trailing actions again.
struct ListActionsToolbar<Primary: View, Apply: View>: ViewModifier {
    @Binding var searchText: String
    @Binding var focusRequest: Bool
    @Binding var showEnabledOnly: Bool
    let searchPrompt: LocalizedStringKey
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let apply: () -> Apply
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var contentWidth: CGFloat = 0
    #endif

    /// A button-style toggle, so the system draws the selected state.
    private var filter: some View {
        Toggle(isOn: $showEnabledOnly) {
            Label("Show Enabled Only", systemImage: "line.3.horizontal.decrease")
        }
        .toggleStyle(.button)
        .help("Show Enabled Only")
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        // Update sits on the leading edge as on iOS, and each trailing action
        // stands alone with the toolbar's own spacing (#999).
        if #available(macOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .navigation) { apply() }
                    .toolbarVisibilityPriorityCompat(.high)
                ToolbarItem(placement: .primaryAction) { filter }
                    .toolbarVisibilityPriorityCompat(.high)
                ToolbarItem(placement: .primaryAction) { primary() }
            }
            .modifier(NativeToolbarSearch(text: $searchText, focusRequest: $focusRequest, prompt: searchPrompt))
            .toolbarBackground(.visible, for: .windowToolbar)
        } else {
            content.toolbar {
                ToolbarItem(placement: .navigation) { apply() }
                ToolbarItem(placement: .primaryAction) {
                    ToolbarSearchField(text: $searchText, isExpanded: $focusRequest, prompt: searchPrompt)
                }
                ToolbarItem(placement: .primaryAction) { filter }
                ToolbarItem(placement: .primaryAction) { primary() }
            }
        }
        #else
        if #available(iOS 26.0, *) {
            content
                .toolbar {
                    if horizontalSizeClass != .regular, focusRequest {
                        ToolbarItem(placement: .topBarLeading) {
                            CompactToolbarSearchField(text: $searchText, prompt: searchPrompt)
                                .frame(width: max(0, contentWidth - 104), height: 36, alignment: .leading)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                searchText = ""
                                withAnimation(.smooth) { focusRequest = false }
                            } label: {
                                Label("Close", systemImage: "xmark")
                            }
                        }
                    } else {
                        ToolbarItem(placement: .topBarLeading) { apply() }
                            .toolbarVisibilityPriorityCompat(.high)
                        // Search, Show Enabled Only, Add: the Mac order (#999).
                        if horizontalSizeClass != .regular {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { withAnimation(.smooth) { focusRequest = true } } label: {
                                    Label("Search", systemImage: "magnifyingglass")
                                }
                            }
                            ToolbarSpacer(.fixed, placement: .topBarTrailing)
                        }
                        ToolbarItem(placement: .topBarTrailing) { filter }
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                        ToolbarItem(placement: .topBarTrailing) { primary() }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        } else {
            // No `if` here: ToolbarContentBuilder can't branch before iOS 16 and
            // crashes on iOS 15.
            content.toolbar {
                ToolbarItem(placement: .navigationBarLeading) { apply() }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if horizontalSizeClass != .regular {
                        Button { focusRequest = true } label: {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) { filter }
                ToolbarItem(placement: .navigationBarTrailing) { primary() }
            }
        }
        #endif
    }
}

#if os(iOS)
/// iPhone search on iOS 26 and later: a field that replaces the toolbar
/// buttons until Close. The system's minimized toolbar search can't be closed
/// reliably on iOS 27: its X loses taps to the neighboring buttons, and a
/// second open leaves a blank field with no X (#984).
private struct CompactToolbarSearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 12)
        .onAppear { isFocused = true }
    }
}
#endif

#if os(macOS)
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
        content.toolbar {
            ToolbarItemGroup(placement: .automatic) { actions() }
        }
    }
}

/// The system toolbar search field. A focus request (⌘F) moves the caret into it
/// and resets, so it can be repeated; `isPresented` alone does not focus it on macOS.
@available(macOS 26.0, *)
private struct NativeToolbarSearch: ViewModifier {
    @Binding var text: String
    @Binding var focusRequest: Bool
    let prompt: LocalizedStringKey
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .searchable(text: $text, placement: .toolbar, prompt: prompt)
            .searchFocused($isFocused)
            .onAppear(perform: handleFocusRequest)
            .onChangeCompat(of: focusRequest) { _, _ in handleFocusRequest() }
    }

    private func handleFocusRequest() {
        guard focusRequest else { return }
        isFocused = true
        focusRequest = false
    }
}

/// The system toolbar search field on macOS 26, and the original toolbar field on older systems.
/// Requests are one-shot so menu and notification commands can focus the field repeatedly.
struct ToolbarSearchModifier: ViewModifier {
    @Binding var text: String
    @Binding var focusRequest: Bool
    let prompt: LocalizedStringKey

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.modifier(NativeToolbarSearch(text: $text, focusRequest: $focusRequest, prompt: prompt))
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

    final class Coordinator {
        var handledRequest = 0
        var pendingFocus: DispatchWorkItem?

        func cancelPendingFocus() {
            pendingFocus?.cancel()
            pendingFocus = nil
        }

        func cancel() {
            cancelPendingFocus()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        if request > 0 {
            context.coordinator.handledRequest = request
            focusSibling(of: view, coordinator: context.coordinator, attemptsLeft: 10)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
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

extension View {
    /// The title of a page pushed inside a tab. macOS hides the window title
    /// behind the tab picker, so it sits in the toolbar beside Back, the way
    /// System Settings shows it (#999).
    func pageTitle(_ title: LocalizedStringKey) -> some View {
        navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .macToolbarTitle(title)
    }

    @ViewBuilder
    func macToolbarTitle(_ title: LocalizedStringKey) -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            toolbar {
                ToolbarItem(placement: .navigation) {
                    Text(title).font(.headline).fixedSize()
                }
                .sharedBackgroundVisibility(.hidden)
                // The first thing to go in a narrow window, ahead of the tabs.
                .toolbarVisibilityPriorityCompat(.low)
            }
        } else {
            toolbar {
                ToolbarItem(placement: .navigation) {
                    Text(title).font(.headline).fixedSize()
                }
            }
        }
        #else
        self
        #endif
    }
}
