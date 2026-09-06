import SwiftUI
import wBlockCoreService

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

extension AddContentRequirement {
    static func localImport(fromFile: Bool) -> [AddContentRequirement] {
        [
            AddContentRequirement(systemImage: "character.cursor.ibeam", text: "Title is required."),
            AddContentRequirement(systemImage: fromFile ? "doc" : "doc.on.clipboard", text: fromFile
                ? "Choose a non-empty text file and review it before adding."
                : "Paste non-empty plain text and review it before adding."),
            AddContentRequirement(systemImage: "arrow.triangle.2.circlepath", text: "Local imports won't auto-update; re-import to replace.")
        ]
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .hiddenListRowSeparatorCompat()
    }
}

struct AddContentField<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AddContentMetadataFields: View {
    @Binding var name: String
    @Binding var description: String
    @Binding var category: FilterListCategory
    let categories: [FilterListCategory]
    var categoryName: (FilterListCategory) -> String = { $0.localizedName }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AddContentField(title: "Name") {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
            }
            AddContentField(title: "Description (optional)") {
                TextField("Description", text: $description)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    #endif
            }
            ContentCategoryPicker(selection: $category, categories: categories, categoryName: categoryName)
        }
    }
}

struct AddContentPasteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .accessibilityLabel("Paste")
    }
}

/// All add modes share the Text tab's glass cards and space for their shadows.
struct AddContentPanelLayout<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                .padding(.vertical, 16)
        }
    }
}

struct AddContentCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .liquidGlassCompat(cornerRadius: 16, material: .regularMaterial)
    }
}

struct AddContentSourceCard<Content: View>: View {
    let title: LocalizedStringKey
    let isDisabled: Bool
    let onPaste: () -> Void
    let onOpenEditor: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        AddContentCard {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content().frame(minHeight: 260)
            Divider()
            HStack(spacing: 10) {
                Button(action: onPaste) { Label("Paste", systemImage: "doc.on.clipboard") }
                Button(action: onOpenEditor) { Label("Use Editor", systemImage: "curlybraces") }
                Spacer()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.accentColor)
            .disabled(isDisabled)
        }
    }
}

struct ContentCategoryPicker: View {
    @Binding var selection: FilterListCategory
    let categories: [FilterListCategory]
    var categoryName: (FilterListCategory) -> String = { $0.localizedName }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            HStack(spacing: 0) { Text("Category"); Text(verbatim: ":") }
                .foregroundStyle(.secondary)
                .fixedSize()
            Picker("Category", selection: $selection) {
                ForEach(categories) { category in
                    Text(categoryName(category)).tag(category)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
