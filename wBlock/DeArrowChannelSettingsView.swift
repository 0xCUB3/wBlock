import SwiftUI
import wBlockCoreService

struct DeArrowChannelSettingsView: View {
    @Binding var settings: DeArrowPreference.Settings
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""

    private var channels: [String] {
        DeArrowPreference.normalizedChannels(settings.originalThumbnailChannels ?? [])
    }

    private var candidate: String? { DeArrowPreference.normalizedChannel(input) }

    var body: some View {
        SheetContainer {
            SheetHeader(title: "Original Thumbnail Channels") { dismiss() }
            VStack(alignment: .leading, spacing: 12) {
                Text("Keep original thumbnails for these YouTube channels.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    channelField
                    Button("Add", action: addChannel)
                        .disabled(candidate == nil || channels.contains(candidate ?? ""))
                }
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(channels, id: \.self) { channel in
                            HStack {
                                Text(verbatim: channel)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(2)
                                Spacer()
                                Button {
                                    let remaining = channels.filter { $0 != channel }
                                    settings.originalThumbnailChannels = remaining.isEmpty ? nil : remaining
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove")
                                .accessibilityValue(channel)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 320, idealHeight: 420)
        #endif
    }

    private var channelField: some View {
        TextField("Channel URL, @handle, or channel ID", text: $input, onCommit: addChannel)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .disableAutocorrection(true)
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif
    }

    private func addChannel() {
        guard let candidate, !channels.contains(candidate) else { return }
        settings.originalThumbnailChannels = DeArrowPreference.normalizedChannels(channels + [candidate])
        input = ""
    }
}
