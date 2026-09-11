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

struct AddContentURLInput: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let isBulk: Bool
    let singlePlaceholder: () -> Text
    let bulkPlaceholder: () -> Text
    let accessibilityLabel: LocalizedStringKey
    let isDisabled: Bool
    let onPaste: () -> Void
    let pasteTitle: LocalizedStringKey
    let pasteButtonUsesRow: Bool
    var macPlaceholderPadding: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isBulk {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .hideEditorBackgroundCompat()
                        .font(.body)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                    if text.isEmpty {
                        bulkPlaceholder()
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            #if os(macOS)
                            .padding(.horizontal, 5)
                            .padding(.vertical, macPlaceholderPadding)
                            #else
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            #endif
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 64, maxHeight: 96)
                .background(Color.urlEditorBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .accessibilityLabel(accessibilityLabel)
            } else {
                TextField("", text: $text, prompt: singlePlaceholder())
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .accessibilityLabel(accessibilityLabel)
            }
            if pasteButtonUsesRow {
                HStack { pasteButton; Spacer() }
            } else {
                pasteButton
            }
        }
    }

    private var pasteButton: some View {
        Button(action: onPaste) {
            Label(pasteTitle, systemImage: "doc.on.clipboard")
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
    }
}

struct AddContentFileSelectionButton: View {
    let filename: String?
    let isLoading: Bool
    let isDisabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: "doc")
                if let filename {
                    Text(filename)
                } else {
                    Text("Choose File")
                }
                if isLoading { ProgressView().controlSize(.small) }
                Spacer()
                if filename != nil { Text("Change File").foregroundStyle(.secondary) }
            }
            #if os(macOS)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )
            #endif
        }
        #if os(macOS)
        .buttonStyle(.plain)
        .noFocusRingCompat()
        #endif
        .disabled(isDisabled)
    }
}

#if os(iOS)
struct AddContentIOSSheet<Content: View>: View {
    let title: LocalizedStringKey
    let isLoading: Bool
    let buttonTitle: () -> LocalizedStringKey
    let isSubmitDisabled: Bool
    let onDismiss: () -> Void
    let onSubmit: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        CompatibleNavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onDismiss)
                            .disabled(isLoading)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: onSubmit) {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text(buttonTitle())
                            }
                        }
                        .disabled(isSubmitDisabled)
                    }
                }
        }
        .interactiveDismissDisabled(isLoading)
        .largeSheetPresentationCompat()
    }
}

#endif

#if os(macOS)
struct AddContentMacSheet<Content: View, Action: View>: View {
    let title: String
    let isLoading: Bool
    let minHeight: CGFloat
    let onDismiss: () -> Void
    let isDismissDisabled: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let action: () -> Action

    var body: some View {
        SheetContainer {
            SheetHeader(title: title, isLoading: isLoading) { onDismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content() }
                    .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
            }
            SheetBottomToolbar {
                Spacer()
                action()
            }
        }
        .interactiveDismissDisabled(isDismissDisabled)
        .frame(minWidth: 560, minHeight: minHeight)
    }
}

#endif

extension Color {
    static var urlEditorBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .textBackgroundColor)
        #endif
    }
}
