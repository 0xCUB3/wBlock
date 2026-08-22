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
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
        #else
        self.background(material, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
        #endif
    }
}

#if os(macOS)
struct ToolbarSearchField: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    var prompt: LocalizedStringKey = "Search"

    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isExpanded {
                HStack(spacing: 6) {
                    TextField(prompt, text: $text)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onExitCommand { collapse() }

                    Button { collapse() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Close search"))
                }
                .padding(.horizontal, 8)
                .frame(width: 180)
                .transition(.blurReplaceCompat)
                .task {
                    try? await TaskSleep.sleep(for: .milliseconds(350))
                    isFocused = true
                }
            } else {
                Button {
                    isExpanded = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .transition(.blurReplaceCompat)
            }
        }
        .animation(.smooth(duration: 0.3), value: isExpanded)
        .onChangeCompat(of: isFocused) { _, focused in
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
