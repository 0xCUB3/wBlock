import SwiftUI

/// The icon controls every source window shares, viewing or editing (#921):
/// one size, one spacing. Enabled controls draw in the primary color and
/// unavailable ones gray out, so gray always means "can't press" (#932).
struct SourceViewerControls<Extra: View>: View {
    @Binding var wrapsLines: Bool
    let onSearch: () -> Void
    var onClose: (() -> Void)?
    /// Grays out every control but Close, which always works.
    var isLoading = false
    @ViewBuilder var extra: () -> Extra

    init(wrapsLines: Binding<Bool>, onSearch: @escaping () -> Void, onClose: (() -> Void)? = nil,
         isLoading: Bool = false, @ViewBuilder extra: @escaping () -> Extra) {
        _wrapsLines = wrapsLines
        self.onSearch = onSearch
        self.onClose = onClose
        self.isLoading = isLoading
        self.extra = extra
    }

    var body: some View {
        HStack(spacing: SourceControlMetrics.spacing) {
            SourceControlCluster {
                extra()
                SourceControlButton("Search", systemImage: "magnifyingglass", action: onSearch)
                    // Works while focus is outside the editor, which handles it itself (#1090).
                    .keyboardShortcut("f", modifiers: .command)
                SourceControlButton("Wrap Lines", systemImage: wrapsLines ? "text.justify.left" : "text.alignleft",
                                    isOn: wrapsLines) { wrapsLines.toggle() }
                    .accessibilityValue(wrapsLines ? String(localized: "On") : String(localized: "Off"))
            }
            .disabled(isLoading)
            if let onClose {
                // The icons sit inset in their frames and the X fills its own,
                // so it needs that inset to look as far from Wrap Lines (#982).
                SheetDoneButton(action: onClose)
                    .padding(.leading, SourceControlMetrics.glyphInset)
            }
        }
    }
}

extension SourceViewerControls where Extra == EmptyView {
    init(wrapsLines: Binding<Bool>, onSearch: @escaping () -> Void, onClose: (() -> Void)? = nil) {
        self.init(wrapsLines: wrapsLines, onSearch: onSearch, onClose: onClose) { EmptyView() }
    }
}

/// Source controls side by side. macOS 26 fuses them into one glass
/// capsule, like a toolbar group (#1091).
struct SourceControlCluster<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Namespace private var namespace

    var body: some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                HStack(spacing: 0) {
                    Group(subviews: content()) { subviews in
                        ForEach(subviews) { $0.glassEffectUnion(id: 0, namespace: namespace) }
                    }
                }
            }
        } else {
            HStack(spacing: SourceControlMetrics.spacing) { content() }
        }
        #else
        HStack(spacing: SourceControlMetrics.spacing) { content() }
        #endif
    }
}

enum SourceControlMetrics {
    static var size: CGFloat {
        #if os(iOS)
        44
        #else
        24
        #endif
    }

    static var spacing: CGFloat {
        #if os(iOS)
        8
        #else
        12
        #endif
    }

    /// Space between an icon's glyph and the edge of its frame. iOS draws the
    /// close button as a glass circle the size of the frame, so it needs none.
    static var glyphInset: CGFloat {
        #if os(iOS)
        0
        #else
        4
        #endif
    }
}

/// An icon-only source control sized like its neighbors.
struct SourceControlButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var isOn = false
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, isOn: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isOn = isOn
        self.action = action
    }

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            // Native glass, like the close button beside them (#1089). A
            // control that's on fills with the accent color, as Show Enabled
            // Only does in the toolbar (#1091).
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .frame(width: 20, height: 20)
            }
            .glassToggleStyle(isOn: isOn)
            .buttonBorderShape(.circle)
            .accessibilityLabel(title)
            .help(title)
        } else {
            plainButton
        }
        #else
        plainButton
        #endif
    }

    private var plainButton: some View {
        Button(action: action) {
            SourceControlIcon(systemImage: systemImage, isOn: isOn)
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .accessibilityLabel(title)
        .help(title)
    }
}

struct SourceControlIcon: View {
    let systemImage: String
    var isOn = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: systemImage)
            .frame(width: SourceControlMetrics.size, height: SourceControlMetrics.size)
            .contentShape(Rectangle())
            .foregroundStyle(isOn ? Color.accentColor : (isEnabled ? Color.primary : Color.secondary.opacity(0.5)))
    }
}

#if os(macOS)
@available(macOS 26.0, *)
private extension View {
    @ViewBuilder
    func glassToggleStyle(isOn: Bool) -> some View {
        if isOn { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
    }
}
#endif

/// The capsule behind a source window's menu, darker while pressed so a
/// click shows (#1088). macOS 26 uses glass like its neighbors (#1089),
/// filled with the accent color while the menu narrows what shows (#1091);
/// elsewhere the icon takes the accent color instead. macOS before 14 can't
/// style a menu as a button and keeps the plain capsule.
struct SourceMenuCapsule: ViewModifier {
    var isActive = false

    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            content.menuStyle(.button).glassToggleStyle(isOn: isActive).buttonBorderShape(.capsule)
        } else if #available(macOS 14.0, *) {
            content.menuStyle(.button).buttonStyle(CapsulePressStyle()).foregroundStyle(tint)
        } else {
            content.menuStyle(.borderlessButton).buttonStyle(.plain)
                .modifier(CapsuleChrome(isPressed: false)).foregroundStyle(tint)
        }
        #else
        content.buttonStyle(CapsulePressStyle()).foregroundStyle(tint)
        #endif
    }

    private var tint: Color { isActive ? .accentColor : .primary }
}

private struct CapsulePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(CapsuleChrome(isPressed: configuration.isPressed))
    }
}

private struct CapsuleChrome: ViewModifier {
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .frame(height: SourceControlMetrics.size)
            .background(Capsule().fill(Color.secondary.opacity(isPressed ? 0.3 : 0.15)))
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.1), value: isPressed)
    }
}
