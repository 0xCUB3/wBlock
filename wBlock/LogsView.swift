//
//  LogsView.swift
//  wBlock
//
//  Created by Alexander Skula on 5/23/25.
//

import SwiftUI
#if os(iOS)
import UIKit

struct SelectableTextView: UIViewRepresentable {
    var text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }
}
#endif

struct LogsView: View {
    @State private var logs: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 15) {
            SheetHeader(title: "wBlock Logs") {
                dismiss()
            }

            // Scrollable text view showing the combined formatted logs.
            #if os(iOS)
            SelectableTextView(text: logs)
                .padding(8)
                .background(Color.clear)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
                .padding(.horizontal)
            #else
            TextEditor(text: .constant(logs)) // Use .constant if TextEditor is read-only
                .font(.system(.body, design: .monospaced))
                .padding(8)
            #if os(macOS)
                .background(Color(NSColor.textBackgroundColor))
            #endif //TODO: add ios color
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
                #if os(iOS)
                .disabled(true)
                #endif
                .padding(.horizontal)
            #endif


            SheetBottomToolbar {
                Button {
                    Task {
                        // Force ingestion of shared auto update log before displaying
                        logs = await ConcurrentLogManager.shared.getAllLogs()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(role: .destructive) {
                    Task {
                        await ConcurrentLogManager.shared.clearLogs()
                        // The "Logs cleared." message will be the only one left after this:
                        logs = await ConcurrentLogManager.shared.getAllLogs()
                    }
                } label: {
                    Label("Clear Logs", systemImage: "trash")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, maxWidth: .infinity,
               minHeight: 500, idealHeight: 650, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .frame(minWidth: 0, idealWidth: .infinity, maxWidth: .infinity,
               minHeight: 0, idealHeight: .infinity, maxHeight: .infinity)
        #endif
        .onAppear {
            Task {
                logs = await ConcurrentLogManager.shared.getAllLogs()
            }
        }
    }
}
