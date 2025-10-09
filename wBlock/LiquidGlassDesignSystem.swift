//
//  LiquidGlassDesignSystem.swift
//  wBlock
//
//  Created by Claude on 10/9/25.
//  Native iOS 26 / macOS 26 Liquid Glass implementation
//

import SwiftUI

// MARK: - Liquid Glass Design System

@available(iOS 26.0, macOS 26.0, *)
struct LiquidGlassDesignSystem {
    // Glass styles for different use cases
    enum GlassStyle {
        case regular
        case regularTinted(Color)
        case regularInteractive
        case clear
        case clearTinted(Color)

        var glass: Glass {
            switch self {
            case .regular:
                return .regular
            case .regularTinted(let color):
                return .regular.tint(color)
            case .regularInteractive:
                return .regular.interactive()
            case .clear:
                return .clear
            case .clearTinted(let color):
                return .clear.tint(color)
            }
        }
    }

    // Standard shapes for liquid glass
    static let standardCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 16
    static let buttonCornerRadius: CGFloat = 10
}

// MARK: - View Extensions for Liquid Glass

@available(iOS 26.0, macOS 26.0, *)
extension View {
    /// Applies liquid glass effect with standard rounded rectangle shape
    func liquidGlass(
        style: LiquidGlassDesignSystem.GlassStyle = .regular,
        cornerRadius: CGFloat = LiquidGlassDesignSystem.standardCornerRadius
    ) -> some View {
        self.glassEffect(style.glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Applies liquid glass effect with capsule shape
    func liquidGlassCapsule(
        style: LiquidGlassDesignSystem.GlassStyle = .regular
    ) -> some View {
        self.glassEffect(style.glass, in: Capsule())
    }

    /// Applies liquid glass effect with custom shape
    func liquidGlass<S: Shape>(
        style: LiquidGlassDesignSystem.GlassStyle = .regular,
        in shape: S
    ) -> some View {
        self.glassEffect(style.glass, in: shape)
    }

    /// Applies interactive liquid glass for buttons and controls
    func liquidGlassInteractive(
        tint: Color? = nil,
        cornerRadius: CGFloat = LiquidGlassDesignSystem.buttonCornerRadius
    ) -> some View {
        let glass = tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive()
        return self.glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Liquid Glass Card Container

@available(iOS 26.0, macOS 26.0, *)
struct LiquidGlassCard<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let style: LiquidGlassDesignSystem.GlassStyle

    init(
        cornerRadius: CGFloat = LiquidGlassDesignSystem.cardCornerRadius,
        style: LiquidGlassDesignSystem.GlassStyle = .regular,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.style = style
    }

    var body: some View {
        content
            .liquidGlass(style: style, cornerRadius: cornerRadius)
    }
}

// MARK: - Liquid Glass Button Style

@available(iOS 26.0, macOS 26.0, *)
struct LiquidGlassButtonStyle: ButtonStyle {
    let tint: Color?
    let cornerRadius: CGFloat

    init(tint: Color? = nil, cornerRadius: CGFloat = LiquidGlassDesignSystem.buttonCornerRadius) {
        self.tint = tint
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .liquidGlassInteractive(tint: tint, cornerRadius: cornerRadius)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Fallback for Earlier OS Versions

// For iOS 25 and earlier, provide graceful fallback using materials
extension View {
    @ViewBuilder
    func liquidGlassCompat(
        cornerRadius: CGFloat = 12,
        material: Material = .regular
    ) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.liquidGlass(cornerRadius: cornerRadius)
        } else {
            self
                .background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func liquidGlassCapsuleCompat(
        material: Material = .regular
    ) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            self.liquidGlassCapsule()
        } else {
            self
                .background(material, in: Capsule())
        }
    }
}

// MARK: - Grouped Glass Container

@available(iOS 26.0, macOS 26.0, *)
struct LiquidGlassGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer {
            content
        }
    }
}
