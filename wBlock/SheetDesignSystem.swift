//
//  SheetDesignSystem.swift
//  wBlock
//
//  Created by Alexander Skula on 10/1/25.
//

import SwiftUI

// MARK: - Design System Constants

enum SheetDesign {
    static let contentHorizontalPadding: CGFloat = 20
}

// MARK: - Reusable Sheet Done Button

struct SheetDoneButton: View {
    let action: () -> Void

    var body: some View {
        Button("Done") {
            action()
        }
        .glassButtonStyleCompat()
        .keyboardShortcut(.cancelAction)
    }
}

// MARK: - Reusable Sheet Header

struct SheetHeader: View {
    let title: String
    let isLoading: Bool
    let onDismiss: () -> Void

    init(title: String, isLoading: Bool = false, onDismiss: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            if !isLoading {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .background(Color.clear)
    }
}

// MARK: - Reusable Bottom Toolbar

struct SheetBottomToolbar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 16) {
            content
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.clear)
    }
}

// MARK: - Sheet Container

struct SheetContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        #endif
    }
}

// MARK: - Standard Button Styles

extension View {
    func primaryActionButtonStyle() -> some View {
        self.buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}
