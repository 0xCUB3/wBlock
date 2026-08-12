//
//  StatCard.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI

struct StatCardMetric {
    let value: String
    let icon: String
    let accessibilityLabel: String
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let valueColor: Color
    let metrics: [StatCardMetric]

    init(
        title: String,
        value: String,
        icon: String,
        valueColor: Color = .primary,
        metrics: [StatCardMetric] = []
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.valueColor = valueColor
        self.metrics = metrics
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(valueColor)
                .frame(width: 30)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey({
                    #if os(iOS)
                    switch title {
                    case "Enabled Lists": "Enabled"
                    case "Applied Rules": "Rules"
                    default: title
                    }
                    #else
                    title
                    #endif
                }()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if metrics.isEmpty {
                    Text(value)
                        .font(.title2.monospacedDigit())
                        .fontWeight(.semibold)
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                        .frame(minWidth: 60, alignment: .leading)
                } else {
                    HStack(spacing: 10) {
                        ForEach(metrics.indices, id: \.self) { index in
                            let metric = metrics[index]
                            HStack(spacing: 3) {
                                Image(systemName: metric.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 12)

                                Text(metric.value)
                                    .font(.title2.monospacedDigit())
                                    .fontWeight(.semibold)
                                    .foregroundStyle(valueColor)
                                    .lineLimit(1)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(metric.accessibilityLabel)
                            .accessibilityValue(metric.value)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        #if os(iOS)
        .frame(maxWidth: .infinity, alignment: .leading)
        #else
        .frame(minWidth: 155)
        #endif
        .background {
            #if os(iOS)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
            #else
            Capsule()
                .fill(.regularMaterial)
            #endif
        }
    }
}
