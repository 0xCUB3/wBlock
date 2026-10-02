//
//  StatCard.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI

/// Both tab summaries share spacing and horizontal clearance.
struct StatsCardsView<Content: View>: View {
    var compact = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: compact ? 8 : 12) { content }
        #if os(iOS)
        .fixedSize(horizontal: false, vertical: true)
        #endif
        .padding(.horizontal)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let valueColor: Color
    /// Folds the icon into the title line so three cards fit an iPhone row.
    let compact: Bool
    /// Draws the row chevron after the title so a tappable card reads as one,
    /// and stands apart from the static cards beside it.
    let showsDisclosure: Bool

    init(
        title: String,
        value: String,
        icon: String,
        valueColor: Color = .primary,
        compact: Bool = false,
        showsDisclosure: Bool = false
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.valueColor = valueColor
        self.compact = compact
        self.showsDisclosure = showsDisclosure
    }

    var body: some View {
        HStack(spacing: 10) {
            if !compact {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(valueColor)
                    .frame(width: 30)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if compact {
                        Image(systemName: icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(LocalizedStringKey({
                    #if os(iOS)
                    switch title {
                    case "Enabled Lists": "Enabled"
                    case "Applied Rules": "Rules"
                    case "Rule Capacity": "Capacity"
                    case "Next Update": "Updates"
                    case "iCloud Sync": "iCloud"
                    default: title
                    }
                    #else
                    title
                    #endif
                    }()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    #if os(iOS)
                    if showsDisclosure {
                        RowDisclosureChevron()
                    }
                    #endif
                }

                Text(value)
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    #if os(iOS)
                    .frame(minWidth: compact ? 0 : 60, alignment: .leading)
                    #endif
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, compact ? 14 : 20)
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
