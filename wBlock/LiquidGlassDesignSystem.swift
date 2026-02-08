//
//  LiquidGlassDesignSystem.swift
//  wBlock
//
//  Created by Alexander Skula on 10/9/25.
//

import SwiftUI

// MARK: - Liquid Glass (wBlock style)

struct LiquidGlassDesignSystem {
    enum GlassStyle: Equatable {
        case regular
        case regularTinted(Color)
        case regularInteractive
        case clear
        case clearTinted(Color)

        var material: Material {
            switch self {
            case .regular, .regularTinted, .regularInteractive:
                return .regularMaterial
            case .clear, .clearTinted:
                return .ultraThinMaterial
            }
        }

        var tint: Color? {
            switch self {
            case .regularTinted(let color), .clearTinted(let color):
                return color
            default:
                return nil
            }
        }
    }

    static let standardCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 16
    static let buttonCornerRadius: CGFloat = 12
}

extension View {
    func liquidGlass(
        style: LiquidGlassDesignSystem.GlassStyle = .regular,
        cornerRadius: CGFloat = LiquidGlassDesignSystem.standardCornerRadius
    ) -> some View {
        self.liquidGlass(style: style, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func liquidGlassCapsule(
        style: LiquidGlassDesignSystem.GlassStyle = .regular
    ) -> some View {
        self.liquidGlass(style: style, in: Capsule())
    }

    func liquidGlass<S: Shape>(
        style: LiquidGlassDesignSystem.GlassStyle = .regular,
        in shape: S
    ) -> some View {
        self
            .background(style.material, in: shape)
            .overlay {
                shape
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .overlay {
                if let tint = style.tint {
                    shape
                        .fill(tint.opacity(0.12))
                        .blendMode(.plusLighter)
                }
            }
    }

    func liquidGlassInteractive(
        tint: Color? = nil,
        cornerRadius: CGFloat = LiquidGlassDesignSystem.buttonCornerRadius
    ) -> some View {
        self.liquidGlass(
            style: tint.map { .regularTinted($0) } ?? .regularInteractive,
            cornerRadius: cornerRadius
        )
    }

    @ViewBuilder
    func liquidGlassCompat(
        cornerRadius: CGFloat = LiquidGlassDesignSystem.standardCornerRadius,
        material: Material = .regularMaterial
    ) -> some View {
        self
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }

    @ViewBuilder
    func liquidGlassCapsuleCompat(
        material: Material = .regularMaterial
    ) -> some View {
        self
            .background(material, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }
}

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

#if os(macOS)
struct ToolbarSearchField: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    var prompt: String = "Search"

    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isExpanded {
                HStack(spacing: 6) {
                    TextField(prompt, text: $text)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onExitCommand { collapse() }

                    if !text.isEmpty {
                        Button { text = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 8)
                .frame(width: 220)
                .transition(.blurReplace)
                .task {
                    try? await Task.sleep(for: .milliseconds(350))
                    isFocused = true
                }
            } else {
                Button {
                    isExpanded = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.3), value: isExpanded)
        .onChange(of: isFocused) { _, focused in
            if !focused && isExpanded {
                collapse()
            }
        }
    }

    private func collapse() {
        text = ""
        isExpanded = false
    }
}
#endif

struct SearchMinimizeBehavior: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            applyMinimize(content)
        } else {
            content
        }
        #else
        content
        #endif
    }

    #if os(iOS)
    @available(iOS 26.0, *)
    private func applyMinimize(_ content: Content) -> some View {
        content.searchToolbarBehavior(.minimize)
    }
    #endif
}

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
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
