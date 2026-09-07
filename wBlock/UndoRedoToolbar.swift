import SwiftUI

struct UndoRedoToolbar: ToolbarContent {
    let canUndo: Bool
    let canRedo: Bool
    let undo: () -> Void
    let redo: () -> Void

    private var placement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: placement) {
            UndoRedoButtons(canUndo: canUndo, canRedo: canRedo, undo: undo, redo: redo)
        }
    }
}

/// The two buttons without a toolbar wrapper, so macOS can place them in a
/// shared glass group apart from search (#771). A builder rather than a View
/// type: wrapped in its own view, AppKit read the first button's name for
/// every button in the toolbar group.
@ViewBuilder
func UndoRedoButtons(
    canUndo: Bool,
    canRedo: Bool,
    undo: @escaping () -> Void,
    redo: @escaping () -> Void
) -> some View {
    Button(action: undo) {
        Label("Undo", systemImage: "arrow.uturn.backward")
    }
    .labelStyle(.iconOnly)
    .help("Undo")
    .disabled(!canUndo)
    Button(action: redo) {
        Label("Redo", systemImage: "arrow.uturn.forward")
    }
    .labelStyle(.iconOnly)
    .help("Redo")
    .disabled(!canRedo)
}
