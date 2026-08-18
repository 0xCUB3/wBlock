//
//  ApplyProgressField.swift
//  wBlock
//
//  Created by Alexander Skula on 10/09/25.
//

import SwiftUI

struct ApplyProgressField: View {
    let presentation: ApplyProgressPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView(value: presentation.progress) {
                Text(presentation.title)
                    .fixedSize(horizontal: false, vertical: true)
            } currentValueLabel: {
                Text(presentation.progressLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .progressViewStyle(.linear)
            .tint(presentation.isFailed ? Color.red : Color.accentColor)
            .accessibilityLabel(String(localized: "Apply Changes"))
            .accessibilityValue(presentation.progressLabel)

            VStack(spacing: 0) {
                ForEach(Array(presentation.nodes.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Divider()
                    }
                    ApplyProgressRow(node: node)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct ApplyProgressRow: View {
    let node: ApplyProgressPresentation.Node

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusLeading
                .frame(width: 16, height: 16)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(node.phase.title)
                        .font(.body)
                        .foregroundStyle(node.status == .pending ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let accessory = node.accessory, !accessory.isEmpty {
                        Spacer(minLength: 8)
                        Text(accessory)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }

                if let detail = node.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
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
