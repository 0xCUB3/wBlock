//
//  ApplyProgressField.swift
//  wBlock
//
//  Created by Alexander Skula on 10/09/25.
//

import SwiftUI

struct ApplyProgressField: View {
    let presentation: ApplyProgressPresentation
    var groupedRows: Bool = {
        #if os(iOS)
        true
        #else
        false
        #endif
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView(value: presentation.progress) {
                Text(presentation.title)
            } currentValueLabel: {
                Text(presentation.progressLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
            .tint(presentation.isFailed ? Color.red : Color.accentColor)
            .accessibilityLabel(String(localized: "Apply Changes"))
            .accessibilityValue(presentation.progressLabel)

            rows
                .padding(.horizontal, groupedRows ? 12 : 0)
                .background {
                    if groupedRows {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Self.groupedFill)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private static var groupedFill: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, node in
                if index > 0 {
                    Divider()
                }
                ApplyProgressRow(node: node)
            }
        }
    }
}

private struct ApplyProgressRow: View {
    let node: ApplyProgressPresentation.Node

    var body: some View {
        HStack(spacing: 10) {
            statusLeading
                .frame(width: 16, height: 16)

            Text(node.phase.title)
                .font(.body)
                .foregroundStyle(node.status == .pending ? .secondary : .primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let detail = node.detail, !detail.isEmpty {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(node.phase.title)
        .accessibilityValue(node.accessibilityValue)
    }

    @ViewBuilder
    private var statusLeading: some View {
        switch node.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.quaternary)
                .imageScale(.small)
        case .active:
            ProgressView()
                .controlSize(.small)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.small)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .imageScale(.small)
        }
    }
}
