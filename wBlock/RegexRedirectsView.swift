import SwiftUI
import wBlockCoreService

/// Manages user-defined regex URL redirects backed by Safari DNR `regexSubstitution` (#1176).
struct RegexRedirectsView: View {
    @ObservedObject var filterManager: AppFilterManager
    @State private var rules: [RegexRedirectPreference.Rule] = RegexRedirectPreference.rules()
    @State private var patternInput = ""
    @State private var replacementInput = ""
    @State private var isDocumentOnly = true
    @State private var searchText = ""
    @State private var editingRule: RegexRedirectPreference.Rule?
    @State private var undoStack: [[RegexRedirectPreference.Rule]] = []
    @State private var redoStack: [[RegexRedirectPreference.Rule]] = []

    private var filteredRules: [RegexRedirectPreference.Rule] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rules }
        return rules.filter {
            $0.pattern.localizedCaseInsensitiveContains(query)
                || $0.replacement.localizedCaseInsensitiveContains(query)
        }
    }

    private var validationError: String? {
        let trimmedPattern = patternInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = replacementInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPattern.isEmpty && trimmedReplacement.isEmpty { return nil }
        return RegexRedirectPreference.validationError(pattern: trimmedPattern, replacement: trimmedReplacement)
    }

    private var canAdd: Bool {
        RegexRedirectPreference.validationError(pattern: patternInput, replacement: replacementInput) == nil
    }

    var body: some View {
        SettingsPage {
            SettingsGroup(
                header: "Add Redirect",
                footer: [
                    "Use a regular expression (with or without /…/) and $1, $2, … for capture groups. Requires Safari 17 or later."
                ]
            ) {
                TextField(
                    "Match pattern",
                    text: $patternInput,
                    prompt: Text("/^https?:\\/\\/(?:www\\.)?medium\\.com\\/(.*)$/")
                )
                .font(.system(.body, design: .monospaced))
                .siteEntryField()

                TextField(
                    "Redirect to",
                    text: $replacementInput,
                    prompt: Text("https://scribe.rawbit.ninja/$1")
                )
                .font(.system(.body, design: .monospaced))
                .siteEntryField()
                .onSubmit(addRule)

                Toggle("Pages only", isOn: $isDocumentOnly)
                    .settingsSwitch()

                if let validationError {
                    Text(validationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(action: addRule) {
                    Label("Add Redirect", systemImage: "plus.circle.fill")
                }
                .disabled(!canAdd)
            }

            if !filteredRules.isEmpty {
                Section {
                    ForEach(filteredRules) { rule in
                        ruleRow(rule)
                    }
                } header: {
                    Text("Redirects")
                }
            } else if rules.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.turn.up.right.circle")
                            .scaledSystemFont(size: 44, relativeTo: .largeTitle)
                            .foregroundStyle(.secondary.opacity(0.6))
                        Text("No Regex Redirects")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Redirect matching URLs automatically using regular expressions and capture groups.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                }
            }
        }
        .pageTitle("Regex Redirects")
        .modifier(SitePageToolbar(
            canUndo: !undoStack.isEmpty,
            canRedo: !redoStack.isEmpty,
            undo: undo,
            redo: redo,
            searchText: $searchText
        ))
        .sheet(item: $editingRule) { rule in
            RegexRedirectRuleEditorSheet(rule: rule) { updated in
                var next = rules
                if let idx = next.firstIndex(where: { $0.id == updated.id }) {
                    next[idx] = updated
                    commit(next)
                }
            }
        }
    }

    private func ruleRow(_ rule: RegexRedirectPreference.Rule) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: rule.pattern)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(verbatim: rule.replacement)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button {
                    editingRule = rule
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.secondary)
                        .scaledSystemFont(size: 18)
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .noFocusRingCompat()
                .accessibilityLabel("Edit")

                Button {
                    commit(rules.filter { $0.id != rule.id })
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .scaledSystemFont(size: 18)
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .noFocusRingCompat()
                .accessibilityLabel("Delete")
            }

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { enabled in
                    var next = rules
                    if let idx = next.firstIndex(where: { $0.id == rule.id }) {
                        next[idx].isEnabled = enabled
                        commit(next)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize()
        }
    }

    private func addRule() {
        guard canAdd else { return }
        let newRule = RegexRedirectPreference.Rule(
            pattern: patternInput.trimmingCharacters(in: .whitespacesAndNewlines),
            replacement: replacementInput.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: true,
            isDocumentOnly: isDocumentOnly
        )
        patternInput = ""
        replacementInput = ""
        commit(rules + [newRule])
    }

    private func commit(_ next: [RegexRedirectPreference.Rule]) {
        guard next != rules else { return }
        undoStack.append(rules)
        redoStack = []
        apply(next)
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(rules)
        apply(previous)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(rules)
        apply(next)
    }

    private func apply(_ next: [RegexRedirectPreference.Rule]) {
        rules = next
        RegexRedirectPreference.setRules(next)
        Task { await filterManager.refreshDNRRules() }
    }
}

private struct RegexRedirectRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pattern: String
    @State private var replacement: String
    @State private var isDocumentOnly: Bool
    private let original: RegexRedirectPreference.Rule
    private let onSave: (RegexRedirectPreference.Rule) -> Void

    init(rule: RegexRedirectPreference.Rule, onSave: @escaping (RegexRedirectPreference.Rule) -> Void) {
        self.original = rule
        self.onSave = onSave
        _pattern = State(initialValue: rule.pattern)
        _replacement = State(initialValue: rule.replacement)
        _isDocumentOnly = State(initialValue: rule.isDocumentOnly)
    }

    private var error: String? {
        RegexRedirectPreference.validationError(pattern: pattern, replacement: replacement)
    }

    var body: some View {
        CompatibleNavigationStack {
            SettingsPage {
                SettingsGroup(header: "Redirect Rule") {
                    TextField("Match pattern", text: $pattern)
                        .font(.system(.body, design: .monospaced))
                        .siteEntryField()
                    TextField("Redirect to", text: $replacement)
                        .font(.system(.body, design: .monospaced))
                        .siteEntryField()
                    Toggle("Pages only", isOn: $isDocumentOnly)
                        .settingsSwitch()
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Redirect")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = original
                        updated.pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.replacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.isDocumentOnly = isDocumentOnly
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(error != nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 280)
        #endif
    }
}
