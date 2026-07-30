//
//  LiquidGlassDesignSystem.swift
//  wBlock
//
//  Created by Alexander Skula on 10/9/25.
//

import SwiftUI
import wBlockCoreService

extension View {
    @ViewBuilder
    func liquidGlassCompat(
        cornerRadius: CGFloat = 12,
        material: Material = .regularMaterial
    ) -> some View {
        self
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
    }
}

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
