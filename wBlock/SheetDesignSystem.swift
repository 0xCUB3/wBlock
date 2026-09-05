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

// MARK: - Reusable Sheet Close Button

/// The shared dismiss control for every sheet and popover. It renders as an X
/// rather than a "Done" label (#619): the sheets it closes are read-only or
/// autosave, so there is nothing to confirm. The `action` may still flush
/// pending work (the code editor hands its text back before dismissing).
struct SheetDoneButton: View {
    let action: () -> Void
    /// Let the surrounding toolbar style the control. Used for the iOS Info
    /// navigation bar, where the system draws its own glass capsule.
    var usesAutomaticStyle = false

    @ViewBuilder
    var body: some View {
        if usesAutomaticStyle {
            Button(action: action) {
                Label("Close", systemImage: "xmark")
            }
            .keyboardShortcut(.cancelAction)
        } else {
            styledCloseButton
        }
    }

    @ViewBuilder
    private var styledCloseButton: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Close")
            .keyboardShortcut(.cancelAction)
        } else {
            filledCloseButton
        }
        #else
        filledCloseButton
        #endif
    }

    private var filledCloseButton: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.gray)
                .font(.title2)
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .accessibilityLabel("Close")
        .keyboardShortcut(.cancelAction)
    }
}

// MARK: - Info sheet chrome

extension View {
    /// iPhone info sheets put the close button in the navigation bar, the way
    /// the userscript info sheet already does, so a long title never squeezes
    /// the X (cameren, Discord). macOS keeps the inline header the callers draw
    /// themselves, so the close button here is iOS-only.
    @ViewBuilder
    func infoSheetChromeCompat(onDismiss: @escaping () -> Void) -> some View {
        #if os(iOS)
        NavigationView {
            ScrollView {
                self.frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    SheetDoneButton(action: onDismiss, usesAutomaticStyle: true)
                }
            }
        }
        .navigationViewStyle(.stack)
        #else
        self
        #endif
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
            dismissControl
                .disabled(isLoading)
                .opacity(isLoading ? 0 : 1)
                .accessibilityHidden(isLoading)
                .transaction { $0.animation = nil }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .background(Color.clear)
    }

    private var dismissControl: some View {
        SheetDoneButton(action: onDismiss)
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
