//
//  LogsView.swift
//  wBlock
//
//  Created by Alexander Skula on 3/11/25.
//

import SwiftUI
import SwiftData

struct LogsView: View {
    let logs: String
    @Environment(\.dismiss) private var dismiss // Works on both

    var body: some View {
        VStack(spacing: 20) {
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
                }
                .buttonStyle(.plain) // .plain works on both
            }
            .padding(.horizontal)

            ScrollView {
                TextEditor(text: .constant(logs))
                    .font(.system(.body, design: .monospaced))
                    .background(Color(uiColor: .secondarySystemBackground)) // Use UIColor
                    .cornerRadius(8)
                    .disabled(true) // Make TextEditor read-only
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(8)
        }
        .padding()
        #if os(macOS)
        .frame(width: 600, height: 400)
        #endif
        .background(Color(uiColor: .systemBackground))
    }
}
