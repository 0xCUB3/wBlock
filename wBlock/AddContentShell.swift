import SwiftUI

protocol AddContentMode: CaseIterable, Identifiable, Hashable {
    var localizedTitle: LocalizedStringKey { get }
    var systemImage: String { get }
}

struct AddContentModePicker<Mode: AddContentMode>: View {
    @Binding private var selection: Mode

    init(selection: Binding<Mode>) {
        _selection = selection
    }

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Array(Mode.allCases)) { mode in
                Label(mode.localizedTitle, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .animation(.easeInOut(duration: 0.15), value: selection)
        .padding(16)
        .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
    }
}

struct AddContentRequirement: Identifiable {
    let id: String
    let systemImage: String
    let text: LocalizedStringKey

    init(systemImage: String, text: LocalizedStringKey) {
        self.id = "\(systemImage):\(String(describing: text))"
        self.systemImage = systemImage
        self.text = text
    }
}

struct AddContentRequirementsPanel: View {
    let requirements: [AddContentRequirement]
    let footer: LocalizedStringKey?

    init(requirements: [AddContentRequirement], footer: LocalizedStringKey? = nil) {
        self.requirements = requirements
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Requirements", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(requirements) { requirement in
                HStack(spacing: 10) {
                    Image(systemName: requirement.systemImage)
                        .foregroundStyle(.secondary)
                    Text(requirement.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
    }
}
