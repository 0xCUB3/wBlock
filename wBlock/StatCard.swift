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
                .foregroundColor(valueColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text({
                    #if os(iOS)
                    switch title {
                    case "Enabled Lists": "Enabled"
                    case "Applied Rules": "Rules"
                    default: title
                    }
                    #else
                    title
                    #endif
                }())
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundColor(valueColor)
                    .frame(minWidth: valueWidth, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
            }
        }
    .padding(.vertical, 12)
    .padding(.horizontal, 20)
        .background(
            Group {
                #if os(iOS)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(pillColor.opacity(0.85))
                    .shadow(color: pillColor.opacity(0.08), radius: 2, x: 0, y: 1)
                #else
                Capsule()
                    .fill(pillColor.opacity(0.85))
                    .shadow(color: pillColor.opacity(0.08), radius: 2, x: 0, y: 1)
                #endif
            }
        )
    }
}
