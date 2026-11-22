import SwiftUI

/// Continuous rounded-rectangle perimeter path starting at 12 o'clock (top center)
/// and tracing clockwise so `trim(from:to:)` grows cleanly from the top.
struct TopCenteredRoundedRectShape: Shape {
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let midX = rect.midX
        var p = Path()
        p.move(to: CGPoint(x: midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

/// Live apply / download progress state rendered around an `IconBadge`.
enum BadgeRingPhase: Equatable {
    case idle
    case queued
    case applying(progress: Double?)
    case completed(token: Int)
    case failed
}

/// Settings-grade squircle icon badge (30pt iOS / 26pt macOS) with optional
/// perimeter apply ring and persistent failure indicator.
struct IconBadge: View {
    let systemName: String
    let tint: Color
    var isOn: Bool = true
    var size: CGFloat = defaultSize
    var ringPhase: BadgeRingPhase = .idle
    var showsFailedDot: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var orbitPhase: CGFloat = 0
    @State private var completionOpacity: Double = 0
    @State private var completionTrim: CGFloat = 0
    @State private var badgeScale: CGFloat = 1.0
    @State private var failedRetractTrim: CGFloat = 0
    @State private var failedRetractOpacity: Double = 0

    static var defaultSize: CGFloat {
        #if os(iOS)
        return 30
        #else
        return 26
        #endif
    }

    private var cornerRadius: CGFloat { size * 0.25 }
    private var ringOutset: CGFloat { 2.5 }
    private var ringSize: CGFloat { size + ringOutset * 2 }
    private var ringCornerRadius: CGFloat { ringSize * 0.25 }

    var body: some View {
        ZStack {
            badgeSquare
                .scaleEffect(badgeScale)

            perimeterRing
                .frame(width: ringSize, height: ringSize)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if showsFailedDot {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 0.5))
                    .offset(x: 2, y: -2)
                    .accessibilityHidden(true)
            }
        }
        .onChangeCompat(of: ringPhase) { _, newPhase in
            handlePhaseChange(newPhase)
        }
        .onAppear {
            if case .applying(let p) = ringPhase, p == nil {
                startOrbitIfNeeded()
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var badgeSquare: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if isOn {
                shape
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.86), tint],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.32), Color.white.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    }
            } else {
                shape
                    .fill(Color.primary.opacity(0.08))
                    .overlay {
                        if colorSchemeContrast == .increased {
                            shape.strokeBorder(Color.primary.opacity(0.32), lineWidth: 1)
                        }
                    }
            }

            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isOn)
    }

    @ViewBuilder
    private var perimeterRing: some View {
        let shape = TopCenteredRoundedRectShape(cornerRadius: ringCornerRadius)
        let strokeStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

        switch ringPhase {
        case .idle:
            if completionOpacity > 0 {
                shape
                    .trim(from: 0, to: completionTrim)
                    .stroke(tint, style: strokeStyle)
                    .opacity(completionOpacity)
            } else if failedRetractOpacity > 0 {
                shape
                    .trim(from: 0, to: failedRetractTrim)
                    .stroke(Color.orange, style: strokeStyle)
                    .opacity(failedRetractOpacity)
            }
        case .queued:
            shape
                .stroke(tint.opacity(0.30), style: strokeStyle)
                .transition(.opacity)
        case .applying(let progress):
            ZStack {
                shape.stroke(tint.opacity(0.18), style: strokeStyle)
                if let progress {
                    shape
                        .trim(from: 0, to: max(0.04, min(1, CGFloat(progress))))
                        .stroke(tint, style: strokeStyle)
                } else if reduceMotion {
                    shape
                        .stroke(tint.opacity(0.65), style: strokeStyle)
                } else {
                    orbitingArc(shape: shape, strokeStyle: strokeStyle)
                }
            }
        case .completed:
            shape
                .trim(from: 0, to: completionTrim)
                .stroke(tint, style: strokeStyle)
                .opacity(completionOpacity)
        case .failed:
            shape
                .trim(from: 0, to: failedRetractTrim)
                .stroke(Color.orange, style: strokeStyle)
                .opacity(failedRetractOpacity)
        }
    }

    @ViewBuilder
    private func orbitingArc(shape: TopCenteredRoundedRectShape, strokeStyle: StrokeStyle) -> some View {
        let start = orbitPhase.truncatingRemainder(dividingBy: 1.0)
        let length: CGFloat = 0.28
        let end = start + length
        ZStack {
            if end <= 1.0 {
                shape
                    .trim(from: start, to: end)
                    .stroke(tint, style: strokeStyle)
            } else {
                shape
                    .trim(from: start, to: 1.0)
                    .stroke(tint, style: strokeStyle)
                shape
                    .trim(from: 0.0, to: end - 1.0)
                    .stroke(tint, style: strokeStyle)
            }
        }
    }

    private func startOrbitIfNeeded() {
        guard !reduceMotion else { return }
        orbitPhase = 0
        withAnimation(.linear(duration: 1.05).repeatForever(autoreverses: false)) {
            orbitPhase = 1.0
        }
    }

    private func handlePhaseChange(_ phase: BadgeRingPhase) {
        switch phase {
        case .applying(let progress):
            completionOpacity = 0
            failedRetractOpacity = 0
            if progress == nil {
                startOrbitIfNeeded()
            }
        case .completed:
            completionTrim = reduceMotion ? 1.0 : 0.75
            completionOpacity = 1.0
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.35)) {
                    completionOpacity = 0
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    completionTrim = 1.0
                    badgeScale = 1.12
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        badgeScale = 1.0
                    }
                    withAnimation(.easeOut(duration: 0.35)) {
                        completionOpacity = 0
                    }
                }
            }
        case .failed:
            failedRetractTrim = 1.0
            failedRetractOpacity = 1.0
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.4)) {
                    failedRetractOpacity = 0
                }
            } else {
                withAnimation(.easeInOut(duration: 0.4)) {
                    failedRetractTrim = 0.0
                    failedRetractOpacity = 0.0
                }
            }
        case .idle, .queued:
            orbitPhase = 0
        }
    }
}

/// Core Protection Trio badge with a 13pt docked bottom-trailing cutout state glyph.
struct CoreTileBadge: View {
    let bundle: CoreProtectionBundle
    let state: BasicBundleState
    var size: CGFloat = IconBadge.defaultSize
    var ringPhase: BadgeRingPhase = .idle
    var showsFailedDot: Bool = false
    var cutoutBackground: Color

    var body: some View {
        IconBadge(
            systemName: bundle.symbolName,
            tint: bundle.tint,
            isOn: state != .off,
            size: size,
            ringPhase: ringPhase,
            showsFailedDot: showsFailedDot
        )
        .overlay(alignment: .bottomTrailing) {
            stateGlyph
                .offset(x: 4, y: 4)
        }
    }

    private var stateGlyph: some View {
        let symbol: String
        let color: Color
        switch state {
        case .on:
            symbol = "checkmark.circle.fill"
            color = Color(red: 0.16, green: 0.78, blue: 0.42)
        case .partlyOn:
            symbol = "circle.lefthalf.filled"
            color = .orange
        case .off:
            symbol = "circle"
            color = .secondary
        }
        return ZStack {
            Circle()
                .fill(cutoutBackground)
                .frame(width: 15, height: 15)
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        }
        .accessibilityHidden(true)
    }
}

/// Dark Reader badge that doubles as a live appearance swatch reflecting
/// Follow System, Always Dark, or Pure Black (OLED).
struct DarkReaderSwatchBadge: View {
    let isOn: Bool
    let followsSystem: Bool
    let pureBlack: Bool
    var size: CGFloat = IconBadge.defaultSize
    var ringPhase: BadgeRingPhase = .idle

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cornerRadius: CGFloat { size * 0.25 }
    private var ringSize: CGFloat { size + 5 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if isOn {
                swatchFill(shape: shape)
                    .overlay {
                        shape.strokeBorder(
                            pureBlack ? Color.white.opacity(0.28) : Color.white.opacity(0.22),
                            lineWidth: 1
                        )
                    }
                Image(systemName: followsSystem ? "circle.lefthalf.filled" : "moon.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(followsSystem ? Color.primary : Color.white)
            } else {
                shape
                    .fill(Color.primary.opacity(0.08))
                    .overlay {
                        if colorSchemeContrast == .increased {
                            shape.strokeBorder(Color.primary.opacity(0.32), lineWidth: 1)
                        }
                    }
                Image(systemName: "moon.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }

            if case .applying = ringPhase {
                IconBadge(
                    systemName: "moon.fill",
                    tint: .indigo,
                    isOn: false,
                    size: size,
                    ringPhase: ringPhase
                )
                .opacity(0)
                TopCenteredRoundedRectShape(cornerRadius: ringSize * 0.25)
                    .stroke(Color.indigo.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: ringSize, height: ringSize)
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isOn)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: followsSystem)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: pureBlack)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func swatchFill(shape: RoundedRectangle) -> some View {
        if followsSystem {
            ZStack {
                shape.fill(
                    LinearGradient(
                        colors: [Color(white: 0.94), Color(white: 0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
        } else if pureBlack {
            shape.fill(Color.black)
        } else {
            shape.fill(
                LinearGradient(
                    colors: [Color(red: 0.19, green: 0.21, blue: 0.30), Color(red: 0.11, green: 0.12, blue: 0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}
