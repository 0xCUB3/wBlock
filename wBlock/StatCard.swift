//
//  StatCard.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI

/// Equal-width summary row shared across platforms; each card takes an equal
/// share of the available width as a rounded rectangle (#1170).
struct StatsCardsView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) { content }
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let valueColor: Color
    /// Draws the row chevron after the title so a tappable card reads as one,
    /// and stands apart from the static cards beside it.
    let showsDisclosure: Bool

    init(
        title: String,
        value: String,
        icon: String,
        valueColor: Color = .primary,
        showsDisclosure: Bool = false
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.valueColor = valueColor
        self.showsDisclosure = showsDisclosure
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .scaledSystemFont(size: 22, relativeTo: .title2)
                .foregroundStyle(valueColor)
                .frame(width: 30)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey({
                        #if os(iOS)
                        switch title {
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
                    if showsDisclosure {
                        RowDisclosureChevron()
                    }
                }

                Text(value)
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            #if os(iOS)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
            #else
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
            #endif
        }
    }
}
