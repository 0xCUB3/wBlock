import SwiftUI

struct ContentSettingsView<Content: View>: View {
    let name: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        InfoContentScrollView { settingsContent.padding(20) }
            .frame(width: 460)
        #else
        settingsContent.padding(20).infoSheetChromeCompat { dismiss() }
        #endif
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings").font(.title2.weight(.semibold))
                    Text(name).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                SheetDoneButton { dismiss() }
            }
            content()
        }
    }
}

/// The Automatic Updates switch both settings sheets lead with, so filter
/// lists and userscripts read the same (#932).
struct AutomaticUpdatesToggle: View {
    let isOn: Bool
    let description: LocalizedStringKey
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Automatic Updates")
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .settingsSwitch()
        .settingsGroup(tint: isOn ? nil : .orange)
    }
}

/// A titled, rounded group for settings sheets and pages, so every control
/// sits on the same leading edge with one header and one footer style (#943).
struct SettingsGroup<Content: View>: View {
    var header: LocalizedStringKey? = nil
    var footer: [LocalizedStringKey] = []
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
            VStack(alignment: .leading, spacing: 8, content: content).settingsGroup()
            ForEach(Array(footer.enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
        }
    }
}

extension View {
    /// Pins the switch to the group's trailing edge on macOS too, where the
    /// plain switch style draws it right after the label.
    @ViewBuilder
    func settingsSwitch() -> some View {
        #if os(macOS)
        toggleStyle(MacTrailingSwitchToggleStyle())
        #else
        toggleStyle(.switch)
        #endif
    }

    /// A shape background instead of cornerRadius: the latter clips, and on
    /// iOS 26 a switch's glass thumb extends past the row's bounds.
    func settingsGroup(tint: Color? = nil) -> some View {
        padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((tint ?? .primary).opacity(tint == nil ? 0.05 : 0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
