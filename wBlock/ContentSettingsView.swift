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
                #if os(macOS)
                SheetDoneButton { dismiss() }
                #endif
            }
            content()
        }
    }
}
