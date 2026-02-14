//
//  StatCard.swift
//  wBlock
//
//  Created by Alexander Skula on 5/24/25.
//

import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let pillColor: Color
    let valueColor: Color

    private let valueWidth: CGFloat = 80

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(valueColor)
                .frame(width: 32)
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

                Text(value)
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(valueColor)
                    .frame(minWidth: valueWidth, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background {
            #if os(iOS)
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
            }
            #else
            if #available(macOS 26.0, *) {
                Capsule()
                    .fill(.regularMaterial)
            } else {
                Capsule()
                    .fill(.regularMaterial)
            }
            #endif
        }
    }
}
