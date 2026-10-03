import SwiftUI

/// The one window for editing source text, shared by Edit Rules, Edit Content
/// and every Use Editor button (#921). It looks like the read-only viewer —
/// title, Search and Wrap, then the editor — and adds Undo, Redo and Paste
/// with Cancel and Done.
struct SourceEditorSheet: View {
    let title: String
    @ObservedObject var editorController: CodeMirrorEditorController
    /// Receives the edited text; return an error message to keep the sheet open.
    let onDone: (String) async -> String?
    /// Defaults to replacing the document with the clipboard.
    var onPaste: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var wrapsLines = false
    @State private var originalText: String?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Text(LocalizedStringKey(title))
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Button("Done", action: finish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(originalText == nil || isSaving)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            HStack(spacing: SourceControlMetrics.spacing) {
                SourceControlButton("Undo", systemImage: "arrow.uturn.backward", action: editorController.undo)
                SourceControlButton("Redo", systemImage: "arrow.uturn.forward", action: editorController.redo)
                // A wider gap sets the history pair apart from the edit tools.
                Spacer().frame(width: SourceControlMetrics.size / 2)
                SourceControlButton("Paste", systemImage: "doc.on.clipboard", action: onPaste ?? pasteClipboard)
                Spacer(minLength: 0)
                SourceViewerControls(wrapsLines: $wrapsLines, onSearch: editorController.openSearch)
            }
            .disabled(originalText == nil || isSaving)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            Divider()
            CodeMirrorTextEditor(controller: editorController, isEditable: true, isLineWrappingEnabled: wrapsLines)
        }
        #if os(macOS)
        .frame(width: 1000, height: 700)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sourceSheetPresentationCompat()
        #endif
        .interactiveDismissDisabled()
        .task { originalText = await editorController.currentText() }
    }

    private func cancel() {
        if let originalText { editorController.replaceText(originalText, markClean: true) }
        dismiss()
    }

    private func pasteClipboard() {
        #if os(iOS)
        let text = UIPasteboard.general.string
        #else
        let text = NSPasteboard.general.string(forType: .string)
        #endif
        if let text { editorController.replaceText(text) }
    }

    private func finish() {
        Task { @MainActor in
            isSaving = true
            let text = await editorController.currentText()
            errorMessage = await onDone(text)
            isSaving = false
            if errorMessage == nil { dismiss() }
        }
    }
}

extension View {
    /// Source windows fill the screen on iPhone and take the large page size
    /// on iPad so landscape gets the width (#921).
    @ViewBuilder
    func sourceSheetPresentationCompat() -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
