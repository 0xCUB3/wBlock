import SwiftUI

/// What a settings row does when chosen, drawn as a trailing glyph on macOS
/// so the row reads correctly before anyone clicks it. iOS lists add their
/// own disclosure chevrons, so the label stays plain there.
enum SettingsRowAccessory {
    /// Pushes another page in the navigation stack.
    case push
    /// Opens a web page in the browser.
    case external
    /// Shows a popover or sheet anchored to the row.
    case popover
    /// Hands off to another app such as Safari's settings.
    case app

    var systemImage: String {
        switch self {
        case .push, .popover: return "chevron.right"
        case .external: return "arrow.up.right"
        case .app: return "arrow.up.forward.app"
        }
    }
}

struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let accessory: SettingsRowAccessory

    init(_ title: LocalizedStringKey, systemImage: String, accessory: SettingsRowAccessory) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
    }

    var body: some View {
        #if os(macOS)
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .frame(width: 20)
            }
            Spacer(minLength: 12)
            Image(systemName: accessory.systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        #else
        // iOS lists draw disclosure chevrons for NavigationLink only, so a
        // sheet-presenting button borrows one to read the same way.
        if accessory == .popover {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        } else {
            Label(title, systemImage: systemImage)
        }
        #endif
    }
}

extension View {
    /// Puts the menu on the trailing edge of a card row. The grouped Form did
    /// this for free; a plain scroll view leaves the menu beside its label.
    @ViewBuilder
    func macTrailingPicker(_ title: LocalizedStringKey) -> some View {
        #if os(macOS)
        CompatibleLabeledContent {
            self.labelsHidden()
                .buttonStyle(.automatic)
        } label: {
            Text(title)
        }
        #else
        self
        #endif
    }
}
