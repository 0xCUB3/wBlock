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
        VStack(alignment: .leading, spacing: 16) {
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
        .toggleStyle(.switch)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        // A shape background instead of cornerRadius: the latter clips, and on
        // iOS 26 the switch's glass thumb extends past the row's bounds.
        .background(Color.orange.opacity(isOn ? 0 : 0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, -8)
    }
}
