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
        VStack(alignment: .leading, spacing: 14) {
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
        // The switch alone in the box with its explanation under it, like a
        // Settings footer (#999).
        SettingsGroup(footer: [description], tint: isOn ? nil : .orange) {
            Toggle("Automatic Updates", isOn: Binding(get: { isOn }, set: onChange))
                .settingsSwitch()
        }
    }
}

extension EnvironmentValues {
    /// Set by `SettingsPage` on macOS, where a page pushed from Settings is a
    /// grouped Form like Settings itself (#1084). Groups and site editors
    /// then draw as form sections and rows instead of their own boxes.
    @Entry var isInSettingsForm = false
}

/// A page pushed from Settings. On macOS it is the same grouped Form as
/// Settings, with its width and switch size (#1084); iOS keeps the cards.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        Form { content() }
            .groupedFormStyleCompat()
            .toggleStyle(MacTrailingSwitchToggleStyle())
            .environment(\.isInSettingsForm, true)
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding()
        }
        #endif
    }
}

/// A titled, rounded group for settings sheets and pages, so every control
/// sits on the same leading edge with one header and one footer style (#943).
/// Inside a `SettingsPage` on macOS it is a form section instead.
struct SettingsGroup<Content: View>: View {
    var header: LocalizedStringKey? = nil
    /// Off for a site field, which draws its own box like Site Settings (#1028).
    var isBoxed = true
    var footer: [LocalizedStringKey] = []
    var tint: Color? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.isInSettingsForm) private var isInSettingsForm

    private var footerText: Text? {
        // One paragraph: separate lines left gaps between the sentences (#999).
        footer.first.map { first in footer.dropFirst().reduce(Text(first)) { $0 + Text(verbatim: " ") + Text($1) } }
    }

    var body: some View {
        if isInSettingsForm {
            Section {
                content()
            } header: {
                if let header { Text(header) }
            } footer: {
                if let footerText { footerText.font(.caption).foregroundStyle(.secondary) }
            }
        } else {
            boxed
        }
    }

    private var boxed: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            }
            if isBoxed {
                VStack(alignment: .leading, spacing: 8, content: content).settingsGroup(tint: tint)
            } else {
                VStack(alignment: .leading, spacing: 8, content: content)
            }
            if let footerText {
                footerText
                    .font(.caption).foregroundStyle(.secondary)
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
            .background(tint.map { $0.opacity(0.08) } ?? .groupFill,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
