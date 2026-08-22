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
    var usesAutomaticStyle = false

    @ViewBuilder
    var body: some View {
        if usesAutomaticStyle {
            doneButton
        } else {
            doneButton.glassButtonStyleCompat()
        }
    }

    private var doneButton: some View {
        Button("Done") {
            action()
        }
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
    enum Fill {
        /// Form-style sheets: gray grouped canvas with inset white cards.
        case grouped
        /// Apply Changes-style sheets: one continuous systemBackground card.
        case system
        /// No opaque fill — system sheet chrome (liquid glass) shows through.
        case clear
    }

    var fill: Fill = .grouped
    let content: Content

    init(fill: Fill = .grouped, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        #if os(iOS)
        .background { fillBackground }
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private var fillBackground: some View {
        switch fill {
        case .grouped:
            Color(.systemGroupedBackground).ignoresSafeArea()
        case .system:
            Color(uiColor: .systemBackground).ignoresSafeArea()
        case .clear:
            EmptyView()
        }
    }
    #endif
}

// MARK: - Standard Button Styles

extension View {
    func primaryActionButtonStyle() -> some View {
        self.buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}
