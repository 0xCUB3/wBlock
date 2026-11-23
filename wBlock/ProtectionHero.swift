import SwiftUI
import wBlockCoreService

extension SafariHealthMonitor {
    func status(
        filterManager: AppFilterManager,
        lastUpdatedDate: Date?
    ) -> SafariHealthStatus {
        let hasHitRuleLimit = filterManager.lastRuleCount > 0
            && filterManager.lastRuleCount >= filterManager.safariRuleCapacity
        let isApplying = filterManager.isApplyInFlight || filterManager.hasQueuedBasicAutoApply
        let isCheckingForUpdates = !isApplying
            && (filterManager.isLoading || filterManager.isAutoUpdateRunning)
        let hasFailed = filterManager.hasError || !filterManager.failedReloadTargets.isEmpty
        return status(
            pausedComponents: filterManager.pausedComponents,
            hasHitRuleLimit: hasHitRuleLimit,
            isApplying: isApplying,
            isCheckingForUpdates: isCheckingForUpdates,
            hasFailed: hasFailed,
            lastUpdatedDate: lastUpdatedDate
        )
    }
}

/// Safari extension status medallion shared by the Filters Hero and Onboarding
/// Safari Setup.
///
/// Shows a calm soft-tinted shield medallion with a 1pt hairline edge when
/// healthy, paused, or failed. Draws a flush 2.5pt progress stroke along the
/// same perimeter while applying (zero extra height or layout shift), and a
/// segmented `N`-arc ring only when Safari extensions are turned off.
struct ExtensionStatusRing: View {
    let arcStates: [Bool]
    let isWelded: Bool
    let status: SafariHealthStatus
    let weldCelebrationCount: Int
    var applyProgress: Double? = nil
    var medallionSize: CGFloat = 56

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gapDegrees: Double = 10

    private var showsProgressRing: Bool {
        status == .applying || status == .checkingForUpdates
    }

    private var showsSegmentedRing: Bool {
        !showsProgressRing && (status.isExtensionDegraded || (!isWelded && gapDegrees > 0.05))
    }

    private var ringLineWidth: CGFloat { medallionSize >= 56 ? 2.5 : 2 }
    private var innerDiscSize: CGFloat { showsSegmentedRing ? medallionSize - 10 : medallionSize }
    private var symbolSize: CGFloat { medallionSize * (24.0 / 56.0) }
    private var emerald: Color { Color(red: 0.16, green: 0.78, blue: 0.42) }

    var body: some View {
        ZStack {
            // Soft tinted medallion disc with subtle hairline edge
            Circle()
                .fill(status.tone.color.opacity(0.12))
                .overlay(
                    Circle()
                        .strokeBorder(
                            status.tone.color.opacity((showsSegmentedRing || showsProgressRing) ? 0 : 0.22),
                            lineWidth: 1
                        )
                )
                .frame(width: innerDiscSize, height: innerDiscSize)

            // Flush perimeter progress ring while applying or checking (zero moat, zero height shift)
            if showsProgressRing {
                applyingRingLayer
                    .frame(width: medallionSize, height: medallionSize)
            } else if showsSegmentedRing {
                // Segmented arc ring only while Safari extensions need attention
                SegmentedExtensionRingShapeLayer(
                    arcStates: arcStates.isEmpty ? Array(repeating: false, count: 5) : arcStates,
                    gapDegrees: gapDegrees,
                    lineWidth: ringLineWidth,
                    litColor: emerald,
                    dimColor: Color.primary.opacity(0.14)
                )
                .frame(width: medallionSize, height: medallionSize)
                .transition(.opacity)
            }

            // Center shield glyph
            shieldSymbol
        }
        .frame(width: medallionSize, height: medallionSize)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showsSegmentedRing)
        .onAppear {
            gapDegrees = isWelded ? 0 : 10
        }
        .onChangeCompat(of: isWelded) { _, welded in
            if welded {
                if reduceMotion {
                    gapDegrees = 0
                } else {
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                        gapDegrees = 0
                    }
                }
            } else {
                if reduceMotion {
                    gapDegrees = 10
                } else {
                    withAnimation(.easeOut(duration: 0.25)) {
                        gapDegrees = 10
                    }
                }
            }
        }
        .onChangeCompat(of: weldCelebrationCount) { _, _ in
            Haptics.play(.success)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var applyingRingLayer: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.16), lineWidth: ringLineWidth)
            if status == .applying, let applyProgress, applyProgress > 0 {
                Circle()
                    .trim(from: 0, to: max(0.05, min(1, CGFloat(applyProgress))))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: applyProgress)
            } else if reduceMotion {
                Circle()
                    .stroke(Color.accentColor.opacity(0.65), lineWidth: ringLineWidth)
            } else {
                IndeterminateOrbitArc(lineWidth: ringLineWidth)
            }
        }
    }

    @ViewBuilder
    private var shieldSymbol: some View {
        let icon = Image(systemName: status.symbolName)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(status.tone.color)

        if #available(iOS 17.0, macOS 14.0, *) {
            icon
                .symbolEffect(.bounce, value: weldCelebrationCount)
        } else {
            icon
        }
    }
}

private struct IndeterminateOrbitArc: View {
    let lineWidth: CGFloat
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(spinning ? 270 : -90))
            .onAppear {
                withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
    }
}

/// Animatable segmented arc ring so `gapDegrees` interpolates smoothly to 0° during weld.
private struct SegmentedExtensionRingShapeLayer: View, Animatable {
    let arcStates: [Bool]
    var gapDegrees: Double
    let lineWidth: CGFloat
    let litColor: Color
    let dimColor: Color

    var animatableData: Double {
        get { gapDegrees }
        set { gapDegrees = newValue }
    }

    var body: some View {
        let count = max(1, arcStates.count)
        let pitch = 360.0 / Double(count)
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let startDeg = -90.0 + Double(index) * pitch + gapDegrees / 2.0
                let endDeg = -90.0 + Double(index + 1) * pitch - gapDegrees / 2.0
                ExtensionArcShape(startDegrees: startDeg, endDegrees: endDeg)
                    .stroke(
                        arcStates[index] ? litColor : dimColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )
            }
        }
    }
}

private struct ExtensionArcShape: Shape {
    var startDegrees: Double
    var endDegrees: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            clockwise: false
        )
        return path
    }
}

/// Subtle `<10%` top radial atmospheric wash drawn on the scroll container behind
/// the hero. Fades cleanly with scroll offset and is hidden under Reduce Transparency.
struct ProtectionAtmosphereWash: View {
    let tone: SafariHealthStatus.Tone
    var scrollFade: Double = 1.0

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if !reduceTransparency && scrollFade > 0.01 {
            let peakOpacity = (colorScheme == .dark ? 0.09 : 0.08) * max(0, min(1, scrollFade))
            RadialGradient(
                colors: [
                    tone.color.opacity(peakOpacity),
                    tone.color.opacity(peakOpacity * 0.35),
                    Color.clear,
                ],
                center: .top,
                startRadius: 8,
                endRadius: 230
            )
            .frame(height: 240)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.35), value: tone)
        }
    }
}

/// Unboxed atmospheric Hero (~126pt healthy) sitting at the top of Basic Filters.
struct ProtectionHero: View {
    let status: SafariHealthStatus
    let arcStates: [Bool]
    let isWelded: Bool
    let weldCelebrationCount: Int
    var applyProgress: Double? = nil
    var statusSubtitleOverride: String? = nil
    let onTapHero: () -> Void
    let onAction: (SafariHealthStatus.Action) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let subtitleText = (status.isProtected ? statusSubtitleOverride : nil)
                ?? status.subtitle(now: context.date)
            VStack(spacing: 10) {
                Button(action: onTapHero) {
                    VStack(spacing: 8) {
                        ExtensionStatusRing(
                            arcStates: arcStates,
                            isWelded: isWelded,
                            status: status,
                            weldCelebrationCount: weldCelebrationCount,
                            applyProgress: applyProgress,
                            medallionSize: 56
                        )

                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Text(status.title)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            Text(subtitleText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .noFocusRingCompat()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("\(status.title). \(subtitleText)"))
                .accessibilityHint(Text("Shows Safari extension status"))

                if let action = status.action, let ctaTitle = status.ctaTitle {
                    Button(ctaTitle) {
                        onAction(action)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(status.tone == .gray ? Color.accentColor : status.tone.color)
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 10)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Compact unhealthy banner surfaced in Advanced mode when Safari extensions are off.
struct SafariHealthCompactBanner: View {
    let status: SafariHealthStatus
    let onTapDetail: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTapDetail) {
                HStack(spacing: 10) {
                    Image(systemName: status.symbolName)
                        .font(.title3)
                        .foregroundStyle(status.tone.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(status.subtitle())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .noFocusRingCompat()

            Button(String(localized: "Open Settings")) {
                onOpenSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(status.tone.color)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Compact bottom status accessory for iOS when status != Protected and the Hero
/// has scrolled off screen or the user is on Extras / Settings.
struct SafariHealthBottomAccessory: View {
    let status: SafariHealthStatus
    let onTap: () -> Void
    let onAction: (SafariHealthStatus.Action) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: status.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(status.tone.color)
                    Text(status.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let action = status.action, let ctaTitle = status.ctaTitle {
                Button(ctaTitle) {
                    onAction(action)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(status.tone == .gray ? Color.accentColor : status.tone.color)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
