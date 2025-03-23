//
//  LogsView.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//

import SwiftUI

struct LogsView: View {
    @State private var logs: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header with title and close button.
            HStack {
                Text("Logs")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            // Scrollable text view showing the combined formatted logs.
            ScrollView {
                TextEditor(text: .constant(logs))
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .disabled(true)
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)

            // Control buttons at the bottom.
            HStack(spacing: 20) {
                Button("Refresh") {
                    Task {
                        logs = await ConcurrentLogManager.shared.getAllLogs()
                    }
                }
                .padding(.horizontal)
                
 Button("Clear") {
                    Task {
                        await ConcurrentLogManager.shared.clearLogs()
                        logs = await ConcurrentLogManager.shared.getAllLogs()
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .frame(width: 600, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            Task {
                logs = await ConcurrentLogManager.shared.getAllLogs()
            }
        }
    }
}
