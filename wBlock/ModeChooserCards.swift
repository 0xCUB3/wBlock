import SwiftUI

/// Step 1 onboarding hero preview for Standard mode, with a plain secondary
/// link below for users who prefer to choose filter lists manually.
struct ModeChooserCards: View {
    let onChooseAdvanced: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            BasicModeMiniPreview()
                .frame(maxWidth: .infinity)
                .frame(height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 1)
                }
                .accessibilityHidden(true)

            Text("Same engine and filter lists either way. You can switch anytime in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onChooseAdvanced) {
                Text("Choose filter lists myself")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .noFocusRingCompat()
        }
    }
}

/// Real non-interactive miniature of Standard mode: tiny hero ring + 3-up core trio.
private struct BasicModeMiniPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var litCount: Int = 3
    @State private var appearPulse: Int = 0

    var body: some View {
        ZStack {
            previewCanvas

            VStack(spacing: 10) {
                // Mini Hero
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.78, blue: 0.42).opacity(0.15))
                            .frame(width: 28, height: 28)
                        Circle()
                            .stroke(Color(red: 0.16, green: 0.78, blue: 0.42), lineWidth: 2)
                            .frame(width: 34, height: 34)
                        miniShield
                    }
                    Capsule()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 52, height: 4.5)
                }

                // Mini 3-up Core Trio
                HStack(spacing: 8) {
                    ForEach(Array(CoreProtectionBundle.allCases.enumerated()), id: \.element.id) { index, bundle in
                        let lit = index < litCount
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(lit ? Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14) : Color.primary.opacity(0.08))
                                    .frame(width: 16, height: 16)
                                    .overlay {
                                        Image(systemName: bundle.symbolName)
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(lit ? Color.accentColor : .secondary)
                                    }
                                Spacer(minLength: 0)
                            }
                            Capsule()
                                .fill(Color.primary.opacity(lit ? 0.35 : 0.14))
                                .frame(height: 4)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.75)
                        }
                        .scaleEffect(lit ? 1.0 : 0.96)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.vertical, 12)
        }
        .onAppear {
            guard !reduceMotion else { return }
            litCount = 0
            appearPulse += 1
            for step in 1...3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.08) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        litCount = step
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var miniShield: some View {
        let icon = Image(systemName: "checkmark.shield.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.42))
        if #available(iOS 17.0, macOS 14.0, *) {
            icon.symbolEffect(.bounce, value: appearPulse)
        } else {
            icon
        }
    }

    private var previewCanvas: Color {
        colorScheme == .dark ? Color.black.opacity(0.25) : Color.primary.opacity(0.035)
    }
}
