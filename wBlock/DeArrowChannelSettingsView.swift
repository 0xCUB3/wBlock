import SwiftUI
import wBlockCoreService

struct DeArrowChannelSettingsView: View {
    @Binding var settings: DeArrowPreference.Settings
    @Environment(\.dismiss) private var dismiss

    private var channels: [String] {
        DeArrowPreference.normalizedChannels(settings.originalThumbnailChannels ?? [])
    }

    var body: some View {
        SheetContainer {
            SheetHeader(title: "Original Thumbnail Channels") { dismiss() }
            VStack(alignment: .leading, spacing: 12) {
                Text("Keep original thumbnails for these YouTube channels.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ScrollView {
                    StringListEditor(
                        title: nil, items: channels,
                        update: { settings.originalThumbnailChannels = $0.isEmpty ? nil : $0 },
                        placeholder: "Channel URL, @handle, or channel ID",
                        normalize: DeArrowPreference.normalizedChannel
                    )
                }
            }
            .padding(20)
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 320, idealHeight: 420)
        #endif
    }
}
