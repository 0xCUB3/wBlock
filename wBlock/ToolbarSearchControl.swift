//
//  ToolbarSearchControl.swift
//  wBlock
//
//  Created by Alexander Skula on 1/27/26.
//

import SwiftUI

struct ToolbarSearchControl: View {
    @Binding var text: String
    @Binding var isActive: Bool
    let placeholder: String

    @FocusState private var isFocused: Bool
    @State private var shimmerPhase: CGFloat = -1

    private var trimmedQuery: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if isActive {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(placeholder, text: $text)
                        .focused($isFocused)
                        .textFieldStyle(.plain)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                    #else
                        .disableAutocorrection(true)
                    #endif

                    if !trimmedQuery.isEmpty {
                        Button {
                            text = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear Search")
                    }

                    Button {
                        collapse()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Search")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minWidth: 220)
                .liquidGlassCapsuleCompat(material: .regularMaterial)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.0),
                                    .white.opacity(0.16),
                                    .white.opacity(0.0),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .blendMode(.plusLighter)
                        .opacity(0.85)
                        .offset(x: shimmerPhase * 260)
                        .blur(radius: 14)
                        .mask(Capsule())
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) {
                    Capsule()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.18),
                                    .white.opacity(0.0),
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 120
                            )
                        )
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
                .compositingGroup()
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .trailing)))
                .onAppear {
                    shimmerPhase = -1
                    withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                        shimmerPhase = 1
                    }
                }
                .onDisappear {
                    shimmerPhase = -1
                }
            } else {
                Button {
                    expand()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.22), value: isActive)
        .onChange(of: isActive) { _, newValue in
            if newValue {
                DispatchQueue.main.async {
                    isFocused = true
                }
            } else {
                isFocused = false
            }
        }
    }

    private func expand() {
        withAnimation(.snappy(duration: 0.22)) {
            isActive = true
        }
    }

    private func collapse() {
        withAnimation(.snappy(duration: 0.22)) {
            isActive = false
        }
        if trimmedQuery.isEmpty {
            text = ""
        }
    }
}
