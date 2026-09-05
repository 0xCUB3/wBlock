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
            Button("Undo", systemImage: "arrow.uturn.backward", action: undo)
                .labelStyle(.iconOnly)
                .help("Undo")
                .disabled(!canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward", action: redo)
                .labelStyle(.iconOnly)
                .help("Redo")
                .disabled(!canRedo)
        }
    }
}
