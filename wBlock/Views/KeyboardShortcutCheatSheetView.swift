//
//  KeyboardShortcutCheatSheetView.swift
//  wBlock
//
//  Created by Alexander Skula on 4/24/25.
//


import SwiftUI

struct KeyboardShortcutCheatSheetView: View {
    @Environment(\.dismiss) private var dismiss

    struct Shortcut: Identifiable {
        let id = UUID()
        let keys: String
        let action: String
    }

    private let shortcuts: [Shortcut] = [
        .init(keys: "⌘R",           action: "Check for Filter Updates"),
        .init(keys: "⌘S",           action: "Apply Filter Changes"),
        .init(keys: "⌘N",           action: "Add Custom Filter"),
        .init(keys: "⇧⌘L",          action: "Show Logs"),
        .init(keys: "⌘,",           action: "Open Settings"),
        .init(keys: "⌥⌘R",          action: "Reset to Default Lists"),
        .init(keys: "⇧⌘F",          action: "Toggle Only Enabled Filters"),
        .init(keys: "⇧⌘K",    action: "Show This Cheat Sheet"),
    ]

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Text("Keyboard Shortcuts")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 8)
            .padding(.horizontal)

            Divider()

            VStack(spacing: 0) {
                ForEach(shortcuts) { shortcut in
                    HStack {
                        Text(shortcut.keys)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(width: 100, alignment: .trailing)
                        Text(shortcut.action)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.leading, 12)
                        Spacer()
                    }
                    .padding(.vertical, 11)
                    .padding(.horizontal, 18)

                    if shortcut.id != shortcuts.last?.id {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            )
            .padding(.horizontal)

            Spacer(minLength: 8)

            Text("Access these via the “wBlock Actions” menu or the shortcut keys listed above.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)
        }
        .frame(width: 400, height: 425)
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}
