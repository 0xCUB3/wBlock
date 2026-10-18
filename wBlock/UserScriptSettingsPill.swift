import SwiftUI

struct UserScriptSettingsPill: View {
    let title: Text
    let systemImage: String
    var chevron: String = "chevron.up.chevron.down"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .imageScale(.small)
            title
                .fontWeight(.medium)
                .lineLimit(1)
            Image(systemName: chevron)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
