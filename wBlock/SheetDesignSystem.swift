//
//  SheetDesignSystem.swift
//  wBlock
//
//  Created by Alexander Skula on 10/1/25.
//

import SwiftUI

// MARK: - Design System Constants

enum SheetDesign {
    // Spacing constants
    static let headerTopPadding: CGFloat = 20
    static let headerHorizontalPadding: CGFloat = 20
    static let contentHorizontalPadding: CGFloat = 20
    static let contentVerticalPadding: CGFloat = 20
    static let bottomToolbarHorizontalPadding: CGFloat = 20
    static let bottomToolbarVerticalPadding: CGFloat = 12

    // Button spacing
    static let buttonSpacing: CGFloat = 16

    // Corner radius
    static let cornerRadius: CGFloat = 10
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
        .padding(.horizontal, SheetDesign.headerHorizontalPadding)
        .padding(.top, SheetDesign.headerTopPadding)
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
        HStack(spacing: SheetDesign.buttonSpacing) {
            content
        }
        .padding(.horizontal, SheetDesign.bottomToolbarHorizontalPadding)
        .padding(.vertical, SheetDesign.bottomToolbarVerticalPadding)
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
    /// Applies consistent primary action button style
    func primaryActionButtonStyle() -> some View {
        self.buttonStyle(.borderedProminent)
            .controlSize(.large)
    }

}

// MARK: - Progress View with Status

struct ProgressViewWithStatus: View {
    let progress: Double
    let statusText: String
    let description: String?

    init(progress: Double, statusText: String, description: String? = nil) {
        self.progress = progress
        self.statusText = statusText
        self.description = description
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .scaleEffect(y: 1.2)
                    .animation(.easeInOut(duration: 0.2), value: progress)

                Text(statusText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .animation(.easeInOut(duration: 0.2), value: statusText)
            }
            .padding(.horizontal)

            if let description = description {
                Text(LocalizedStringKey(description))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .transition(.opacity)
    }
}
