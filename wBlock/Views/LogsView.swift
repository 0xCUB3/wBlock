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
    @Environment(\.dismiss) private var dismiss

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
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            ScrollView {
                TextEditor(text: .constant(logs))
                    .font(.system(.body, design: .monospaced))
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
            }
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .frame(width: 600, height: 400)
        .background(Color(.windowBackgroundColor))
    }
}
