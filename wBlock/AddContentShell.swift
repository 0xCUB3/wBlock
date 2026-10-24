import SwiftUI
import wBlockCoreService

protocol AddContentMode: CaseIterable, Identifiable, Hashable {
    var localizedTitle: LocalizedStringKey { get }
    var systemImage: String { get }
}

/// Both Add sheets: grouped forms switched by a bottom tab bar on iOS and a
/// segmented control on macOS (a Mac tab view boxes its content in gray,
/// #1018), with Cancel and the primary action where each platform puts them. On iOS each tab owns its navigation bar, so a bar's
/// scroll-edge blur sized for one form never lingers over another.
struct AddContentSheet<Mode: AddContentMode, Content: View>: View {
    let title: LocalizedStringKey
    @Binding var mode: Mode
    let isLoading: Bool
    let submitTitle: LocalizedStringKey
    let isSubmitDisabled: Bool
    let onDismiss: () -> Void
    let onSubmit: () -> Void
    /// Off when the primary action only closes the sheet, as Cancel would.
    var showsCancel = true
    /// Set while reviewing, to return to the entry step: bottom left on
    /// macOS, in place of Cancel on iOS.
    var onBack: (() -> Void)? = nil
    @ViewBuilder let content: (Mode) -> Content

    var body: some View {
        #if os(iOS)
        tabs
        .interactiveDismissDisabled(isLoading)
        .largeSheetPresentationCompat()
        #else
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).padding([.horizontal, .top], 20)
            Picker(selection: $mode) {
                ForEach(Array(Mode.allCases)) { Text($0.localizedTitle).tag($0) }
            } label: {
                Text(title)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            page(mode)
            HStack {
                if let onBack { backButton(onBack) }
                Spacer()
                if showsCancel { cancelButton.keyboardShortcut(.cancelAction) }
                submitButton
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding([.horizontal, .bottom], 20)
        }
        // A fixed size; the grouped form scrolls inside it (#971).
        .frame(width: 560, height: 520)
        .interactiveDismissDisabled(isLoading)
        #endif
    }

    #if os(iOS)
    private var tabs: some View {
        TabView(selection: $mode) {
            ForEach(Array(Mode.allCases)) { mode in
                page(mode)
                    .tabItem { Label(mode.localizedTitle, systemImage: mode.systemImage) }
                    .tag(mode)
            }
        }
    }
    #endif

    @ViewBuilder
    private func page(_ mode: Mode) -> some View {
        #if os(iOS)
        CompatibleNavigationStack {
            Form { content(mode) }
                .groupedFormStyleCompat()
                .disabled(isLoading)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Branch inside the item: ToolbarContentBuilder can't before iOS 16.
                    ToolbarItem(placement: .cancellationAction) {
                        if let onBack { backButton(onBack) } else if showsCancel { cancelButton }
                    }
                    ToolbarItem(placement: .confirmationAction) { submitButton }
                }
        }
        #else
        Form { content(mode) }
            .groupedFormStyleCompat()
            .disabled(isLoading)
        #endif
    }

    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label("Back", systemImage: "chevron.left") }.disabled(isLoading)
    }

    private var cancelButton: some View {
        Button("Cancel", action: onDismiss).disabled(isLoading)
    }

    private var submitButton: some View {
        Button(action: onSubmit) {
            AddContentSubmitLabel(title: submitTitle, isLoading: isLoading)
        }
        .disabled(isSubmitDisabled)
    }
}

/// One short line under the input instead of a requirements list.
struct AddContentNote: View {
    var text: LocalizedStringKey? = nil
    var error: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let text { Text(text).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.orange) }
        }
        #if os(macOS)
        .font(.caption)
        #else
        .font(.footnote)
        #endif
    }
}

/// Form rows for a list's name, description, category, and Regional languages.
struct AddContentMetadataFields: View {
    @Binding var name: String
    @Binding var description: String
    @Binding var category: FilterListCategory
    let categories: [FilterListCategory]
    var categoryName: (FilterListCategory) -> String = { $0.localizedName }
    /// Filter lists pass this so a Regional list can name its languages.
    var languages: Binding<Set<String>>? = nil

    var body: some View {
        // The label is the placeholder, as on iOS. macOS grouped forms
        // right-align a labeled field, where a typed trailing space never
        // shows (#1039).
        TextField("Name", text: $name, prompt: Text("Name"))
            .labelsHidden()
            .disableAutocorrection(true)
            #if os(iOS)
            .textInputAutocapitalization(.words)
            #endif
        TextField("Description", text: $description, prompt: Text("Description"))
            .labelsHidden()
            .disableAutocorrection(true)
            #if os(iOS)
            .textInputAutocapitalization(.sentences)
            #endif
        ContentCategoryPicker(selection: $category, categories: categories, categoryName: categoryName)
        if let languages {
            RegionalListLanguagesField(category: category, languages: languages)
        }
    }
}

/// Fills metadata fields from source headers until the user edits them.
struct EditorMetadataAutofillState: Equatable {
    private(set) var lastAutofilledName = ""
    private(set) var lastAutofilledDescription = ""
    private(set) var nameWasManuallyEdited = false
    private(set) var descriptionWasManuallyEdited = false

    mutating func autofill(
        name metadataName: String,
        description metadataDescription: String,
        currentName: String,
        currentDescription: String
    ) -> (name: String, description: String) {
        let name = metadataName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = metadataDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameWasManuallyEdited {
            lastAutofilledName = name
        }
        if !descriptionWasManuallyEdited {
            lastAutofilledDescription = description
        }
        return (
            nameWasManuallyEdited ? currentName : lastAutofilledName,
            descriptionWasManuallyEdited ? currentDescription : lastAutofilledDescription
        )
    }

    mutating func noteNameEdit(_ value: String) {
        if value != lastAutofilledName { nameWasManuallyEdited = true }
    }

    mutating func noteDescriptionEdit(_ value: String) {
        if value != lastAutofilledDescription { descriptionWasManuallyEdited = true }
    }
}

/// One reviewed URL with the same metadata fields as local imports.
struct AddContentURLMetadataSection<Footer: View>: View {
    let url: URL
    @Binding var name: String
    @Binding var description: String
    @Binding var category: FilterListCategory
    let categories: [FilterListCategory]
    var categoryName: (FilterListCategory) -> String = { $0.localizedName }
    var languages: Binding<Set<String>>? = nil
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        Section {
            AddContentMetadataFields(name: $name, description: $description, category: $category,
                                     categories: categories, categoryName: categoryName, languages: languages)
        } header: {
            Text(verbatim: url.absoluteString)
                .textCase(nil)
                .lineLimit(1)
                .truncationMode(.middle)
        } footer: {
            footer()
        }
    }
}

/// Text mode: the pasted source, then Paste and Use Editor.
struct AddContentSourceSection<Content: View, Footer: View>: View {
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    let isEmpty: Bool
    let isDisabled: Bool
    let onPaste: () -> Void
    let onOpenEditor: () -> Void
    /// The editor's font and where it draws its first glyph, so the placeholder
    /// sits exactly where typed text will (#950). Defaults match TextEditor.
    var font: Font = .system(.body, design: .monospaced)
    var textInsets = textEditorTextInsets
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        Section {
            content()
                .font(font)
                .overlay(alignment: .topLeading) {
                    if isEmpty {
                        Text(placeholder)
                            .font(font)
                            .foregroundStyle(.secondary)
                            .padding(textInsets)
                            .allowsHitTesting(false)
                    }
                }
                .addContentEditorBox()
                .frame(minHeight: 200)
            AddContentActionRow {
                Button(action: onPaste) { Label("Paste", systemImage: "doc.on.clipboard") }
                Button(action: onOpenEditor) { Label("Use Editor", systemImage: "curlybraces") }
            }
            .disabled(isDisabled)
        } header: {
            Text(title)
        } footer: {
            footer()
        }
    }
}

#if os(macOS)
private let textEditorTextInsets = EdgeInsets(top: 0, leading: 5, bottom: 0, trailing: 5)
#else
private let textEditorTextInsets = EdgeInsets(top: 8, leading: 5, bottom: 8, trailing: 5)
#endif

/// The add button keeps its title's size while working: the title stays in
/// layout, hidden, under a small spinner (#921).
struct AddContentSubmitLabel: View {
    let title: LocalizedStringKey
    let isLoading: Bool

    var body: some View {
        Text(title)
            .opacity(isLoading ? 0 : 1)
            .overlay { if isLoading { ProgressView().controlSize(.small) } }
    }
}

struct ContentCategoryPicker: View {
    @Binding var selection: FilterListCategory
    let categories: [FilterListCategory]
    var categoryName: (FilterListCategory) -> String = { $0.localizedName }

    var body: some View {
        Picker(selection: $selection) {
            ForEach(categories) { category in
                Text(categoryName(category)).tag(category)
            }
        } label: {
            Text("Category")
        }
        .pickerStyle(.menu)
    }
}

/// URL rows: one field or a multi-line editor, then Paste and, for bulk
/// entry, Import File.
struct AddContentURLInput: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let isBulk: Bool
    let placeholder: Text
    let label: LocalizedStringKey
    let isDisabled: Bool
    let onPaste: () -> Void
    let pasteTitle: LocalizedStringKey
    var onImportFile: () -> Void = {}
    var isImportingFile = false

    var body: some View {
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
                    placeholder
                        .font(.body)
                        #if os(iOS)
                        .foregroundStyle(Color(uiColor: .placeholderText))
                        #else
                        .foregroundStyle(Color(nsColor: .placeholderTextColor))
                        #endif
                        .padding(.horizontal, 5)
                        #if os(iOS)
                        .padding(.vertical, 8)
                        #endif
                        .allowsHitTesting(false)
                }
            }
            .addContentEditorBox()
            .frame(minHeight: 96, maxHeight: 140)
            .accessibilityLabel(label)
        } else {
            // Forms on macOS put the label beside the field, which pushed it out
            // of line with the bulk and text editors; the placeholder names it.
            TextField(label, text: $text, prompt: placeholder)
                .labelsHidden()
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .autocorrectionDisabled()
                .focused($isFocused)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
        }
        AddContentActionRow {
            Button(action: onPaste) { Label(pasteTitle, systemImage: "doc.on.clipboard") }
                .disabled(isDisabled)
            if isBulk {
                Button(action: onImportFile) {
                    HStack {
                        Label("Import File", systemImage: "doc")
                        if isImportingFile { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isDisabled || isImportingFile)
            }
        }
    }
}

/// Secondary actions: one row per button on iOS, side by side on macOS.
struct AddContentActionRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(macOS)
        HStack { content() }
        #else
        content()
        #endif
    }
}

struct AddContentFileSelectionButton: View {
    let filename: String?
    let isLoading: Bool
    let isDisabled: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack {
            if let filename {
                Label { Text(verbatim: filename) } icon: { Image(systemName: "doc") }
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            if isLoading { ProgressView().controlSize(.small) }
            Button(action: onSelect) {
                if filename == nil {
                    Label("Choose File", systemImage: "doc")
                } else {
                    Text("Change File")
                }
            }
            .disabled(isDisabled)
        }
    }
}

extension View {
    /// On macOS a multi-line editor needs the text background and a hairline
    /// border to read as editable; iOS Form rows already provide that.
    @ViewBuilder
    func addContentEditorBox() -> some View {
        #if os(macOS)
        self
            .padding(4)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        #else
        self
        #endif
    }
}
