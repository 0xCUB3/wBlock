import SwiftUI

/// The icon controls every source window shares, viewing or editing (#921):
/// one size, one spacing. Enabled controls draw in the primary color and
/// unavailable ones gray out, so gray always means "can't press" (#932).
struct SourceViewerControls<Extra: View>: View {
    @Binding var wrapsLines: Bool
    let onSearch: () -> Void
    @ViewBuilder var extra: () -> Extra

    init(wrapsLines: Binding<Bool>, onSearch: @escaping () -> Void,
         @ViewBuilder extra: @escaping () -> Extra) {
        _wrapsLines = wrapsLines
        self.onSearch = onSearch
        self.extra = extra
    }

    var body: some View {
        HStack(spacing: SourceControlMetrics.spacing) {
            extra()
            SourceControlButton("Search", systemImage: "magnifyingglass", action: onSearch)
            SourceControlButton("Wrap Lines", systemImage: wrapsLines ? "text.justify.left" : "text.alignleft",
                                isOn: wrapsLines) { wrapsLines.toggle() }
                .accessibilityValue(wrapsLines ? String(localized: "On") : String(localized: "Off"))
        }
    }
}

extension SourceViewerControls where Extra == EmptyView {
    init(wrapsLines: Binding<Bool>, onSearch: @escaping () -> Void) {
        self.init(wrapsLines: wrapsLines, onSearch: onSearch) { EmptyView() }
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

    var body: some View {
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
