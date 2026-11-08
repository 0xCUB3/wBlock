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
            // The View menu keeps a bubble of its own, as a toolbar gives a
            // menu (#1092).
            extra().disabled(isLoading)
            SourceControlCluster {
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

/// Source controls side by side. iOS and macOS 26 put them in one glass
/// capsule as tall as the glass close button, like a toolbar group, and it
/// flashes when clicked as glass does (#1091, #1092, #1099). Each control
/// inside is drawn by `SourceClusterItemStyle`; glass buttons merged with a
/// glass union came apart and drew off center.
struct SourceControlCluster<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            HStack(spacing: 0) { content() }
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            HStack(spacing: SourceControlMetrics.spacing) { content() }
        }
    }
}

enum SourceControlMetrics {
    /// A menu label's height. Glass pads it to the close button's height.
    static var menuLabelHeight: CGFloat {
        if #available(iOS 26.0, macOS 26.0, *) { return 20 }
        return size
    }

    /// A glass cluster item's height, which with its 2pt inset matches the
    /// glass close button: 28pt on macOS, 34pt on iOS.
    static var clusterItemHeight: CGFloat {
        #if os(iOS)
        30
        #else
        24
        #endif
    }

    static var size: CGFloat {
        #if os(iOS)
        44
        #else
        24
        #endif
    }

    static var spacing: CGFloat {
        #if os(iOS)
        if #available(iOS 26.0, *) { return 12 }
        return 8
        #else
        return 12
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
        if #available(iOS 26.0, macOS 26.0, *) {
            Button(action: action) {
                Image(systemName: systemImage).frame(width: 20, height: 20)
            }
            .buttonStyle(SourceClusterItemStyle(isOn: isOn))
            .accessibilityLabel(title)
            .help(title)
        } else {
            plainButton
        }
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

/// A control inside a `SourceControlCluster`'s capsule. One that's on fills
/// with the accent color, as Show Enabled Only does in the toolbar (#1091).
struct SourceClusterItemStyle: ButtonStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        Item(label: configuration.label, isOn: isOn, isPressed: configuration.isPressed)
    }

    private struct Item: View {
        let label: Configuration.Label
        let isOn: Bool
        let isPressed: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .font(.body.weight(.medium))
                .padding(.horizontal, 8)
                .frame(minWidth: 36, minHeight: SourceControlMetrics.clusterItemHeight)
                .foregroundStyle(isOn ? Color.white : (isEnabled ? Color.primary : Color.secondary.opacity(0.5)))
                .background {
                    if isOn {
                        Capsule().fill(Color.accentColor.opacity(isPressed ? 0.8 : 1))
                    } else if isPressed {
                        Capsule().fill(Color.primary.opacity(0.12))
                    }
                }
                .padding(2)
                .contentShape(Capsule())
        }
    }
}

/// The capsule behind a source window's menu, darker while pressed so a
/// click shows (#1088). iOS and macOS 26 draw it as a glass capsule of its
/// own like the source controls (#1092, #1097, #1099), filled with the accent
/// color while the menu narrows what shows (#1091); elsewhere the icon takes
/// the accent color instead. macOS before 14 can't style a menu as a
/// button and keeps the plain capsule.
struct SourceMenuCapsule: ViewModifier {
    var isActive = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            // The same glass capsule, item style and click flash as Search
            // and Wrap Lines beside it; a .glass button drew a shorter bubble
            // of a different shape (#1097). The label brings its own chevron.
            content
                #if os(macOS)
                .menuStyle(.button)
                .menuIndicator(.hidden)
                #endif
                .buttonStyle(SourceClusterItemStyle(isOn: isActive))
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            fallback(content)
        }
    }

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 14.0, *) {
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
