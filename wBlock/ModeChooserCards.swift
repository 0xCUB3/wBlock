import SwiftUI

/// Step 1 onboarding mode selector with live miniature UI previews.
/// Side-by-side on macOS / regular iPad, stacked vertically on compact iPhone.
/// Zero hue shift between mode cards: both share neutral card surfaces and use
/// the system accent color strictly for selection state.
struct ModeChooserCards: View {
    @Binding var selectedMode: AppMode

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var basicSelectPulse = 0

    private var usesHorizontalLayout: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if usesHorizontalLayout {
                HStack(alignment: .top, spacing: 12) {
                    basicCard
                    advancedCard
                }
            } else {
                VStack(spacing: 12) {
                    basicCard
                    advancedCard
                }
            }

            Text("You can switch to Advanced or Basic at any time in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
    }

    private var basicCard: some View {
        ModeOptionCard(
            title: "Set it up for me",
            subtitle: "Simple on/off switches, with preconfigured sets of filter lists.",
            badge: "Recommended",
            isSelected: selectedMode == .basic,
            action: {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8)) {
                    selectedMode = .basic
                }
                basicSelectPulse += 1
            }
        ) {
            BasicModeMiniPreview(
                isSelected: selectedMode == .basic,
                pulseToken: basicSelectPulse
            )
        }
    }

    private var advancedCard: some View {
        ModeOptionCard(
            title: "I'll choose filter lists myself",
            subtitle: "You configure your own filter lists by name, add custom ones, and see rule counts.",
            badge: nil,
            isSelected: selectedMode == .advanced,
            action: {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8)) {
                    selectedMode = .advanced
                }
            }
        ) {
            AdvancedModeMiniPreview(isSelected: selectedMode == .advanced)
        }
    }
}

private struct ModeOptionCard<Preview: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let badge: LocalizedStringKey?
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                preview()
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))
                    }

                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var cardSurface: Color {
        #if os(iOS)
        colorScheme == .dark ? Color(.secondarySystemGroupedBackground) : Color(.systemBackground)
        #else
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.85)
        #endif
    }
}

/// Real non-interactive miniature of Basic mode: tiny hero ring + 3-up core trio.
/// Stagger-flips tiles and bounces the shield when selected.
private struct BasicModeMiniPreview: View {
    let isSelected: Bool
    let pulseToken: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var litCount: Int = 3

    var body: some View {
        ZStack {
            previewCanvas

            VStack(spacing: 8) {
                // Mini Hero
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.16, green: 0.78, blue: 0.42).opacity(0.15))
                            .frame(width: 24, height: 24)
                        Circle()
                            .stroke(Color(red: 0.16, green: 0.78, blue: 0.42), lineWidth: 2)
                            .frame(width: 30, height: 30)
                        miniShield
                    }
                    Capsule()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 44, height: 4)
                }

                // Mini 3-up Core Trio
                HStack(spacing: 6) {
                    ForEach(Array(CoreProtectionBundle.allCases.enumerated()), id: \.element.id) { index, bundle in
                        let lit = index < litCount
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(lit ? bundle.tint : Color.primary.opacity(0.12))
                                    .frame(width: 14, height: 14)
                                    .overlay {
                                        Image(systemName: bundle.symbolName)
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(lit ? .white : .secondary)
                                    }
                                Spacer(minLength: 0)
                            }
                            Capsule()
                                .fill(Color.primary.opacity(lit ? 0.35 : 0.14))
                                .frame(height: 3.5)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(lit ? bundle.tint.opacity(colorScheme == .dark ? 0.18 : 0.10) : Color.primary.opacity(0.05))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(lit ? bundle.tint.opacity(0.25) : Color.clear, lineWidth: 0.75)
                        }
                        .scaleEffect(lit ? 1.0 : 0.96)
                    }
                }
                .padding(.horizontal, 10)
            }
            .padding(.vertical, 10)
        }
        .onChangeCompat(of: pulseToken) { _, _ in
            guard isSelected, !reduceMotion else {
                litCount = 3
                return
            }
            litCount = 0
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
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(red: 0.16, green: 0.78, blue: 0.42))
        if #available(iOS 17.0, macOS 14.0, *) {
            icon.symbolEffect(.bounce, value: pulseToken)
        } else {
            icon
        }
    }

    private var previewCanvas: Color {
        colorScheme == .dark ? Color.black.opacity(0.25) : Color.primary.opacity(0.035)
    }
}

/// Real non-interactive miniature of Advanced mode: search capsule, 62% capacity
/// bar, and dense filter rows with toggle switches.
private struct AdvancedModeMiniPreview: View {
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black.opacity(0.25) : Color.primary.opacity(0.035))

            VStack(spacing: 6) {
                // Mini search capsule + Apply pill
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Capsule()
                            .fill(Color.primary.opacity(0.16))
                            .frame(width: 48, height: 3.5)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 15)
                    .background(Color.primary.opacity(0.07), in: Capsule())

                    Capsule()
                        .fill(Color.accentColor.opacity(isSelected ? 0.85 : 0.45))
                        .frame(width: 28, height: 15)
                }

                // 62% rule capacity bar
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.10))
                        Capsule()
                            .fill(Color.accentColor.opacity(0.75))
                            .frame(width: proxy.size.width * 0.62)
                    }
                }
                .frame(height: 5)

                // Dense rows
                VStack(spacing: 4) {
                    miniRow(width: 0.68, on: true)
                    miniRow(width: 0.54, on: true)
                    miniRow(width: 0.76, on: false)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.85))
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
    }

    private func miniRow(width: CGFloat, on: Bool) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.primary.opacity(0.32))
                        .frame(width: proxy.size.width * width, height: 3.5)
                }
                .frame(height: 4)
                Capsule()
                    .fill(Color.primary.opacity(0.14))
                    .frame(width: 42, height: 2.5)
            }
            Spacer(minLength: 4)
            Capsule()
                .fill(on ? Color(red: 0.16, green: 0.78, blue: 0.42).opacity(0.85) : Color.primary.opacity(0.14))
                .frame(width: 16, height: 9)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .padding(1)
                }
        }
    }
}
