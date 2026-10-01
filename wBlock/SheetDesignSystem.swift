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

    @ViewBuilder
    var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            // A bare glyph makes the glass capsule shorter than the neighboring
            // text buttons; sizing the label to a text line and asking for a
            // circle keeps the X round and level with Save (cameren, Discord).
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
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
    /// iPhone info sheets scroll their content directly under the grabber. The
    /// close button sits in the heading row the callers draw, on every platform,
    /// so there is no empty navigation bar above the title (#793). The title
    /// wraps beside the X instead of squeezing it (cameren, Discord). macOS
    /// popovers follow the content height up to a cap, then scroll, so content
    /// that grows while open (adding regional languages) stays reachable.
    @ViewBuilder
    func infoSheetChromeCompat(onDismiss: @escaping () -> Void) -> some View {
        #if os(iOS)
        ScrollView {
            self.frame(maxWidth: .infinity, alignment: .leading)
        }
        #else
        InfoContentScrollView { self }.frame(width: 420)
        #endif
    }
}

// MARK: - Fixed-header info sheets

/// An info sheet keeps its title and dismiss control outside the scroll view.
struct InfoSheetContainer<Header: View, Content: View>: View {
    let header: () -> Header
    let content: () -> Content
    #if os(macOS)
    @State private var headerHeight: CGFloat = 0
    #else
    @State private var isScrolled = false
    #endif

    init(@ViewBuilder header: @escaping () -> Header, @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            header()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: InfoSheetHeaderHeight.self, value: proxy.size.height)
                })
                .onPreferenceChange(InfoSheetHeaderHeight.self) { headerHeight = $0 }
            InfoContentScrollView(maximumHeight: max(0, 640 - headerHeight)) {
                scrollContent
            }
            #else
            ScrollView {
                scrollContent
                    .padding(.top, 4)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(
                            key: InfoSheetScrollOffset.self,
                            value: proxy.frame(in: .named(InfoSheetScrollOffset.space)).minY
                        )
                    })
            }
            .coordinateSpace(name: InfoSheetScrollOffset.space)
            .onPreferenceChange(InfoSheetScrollOffset.self) { isScrolled = $0 < -1 }
            .safeAreaInset(edge: .top, spacing: 0) {
                // Frosted only once content scrolls beneath it, so the title and
                // description do not sit against a divider at rest.
                header()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isScrolled ? AnyShapeStyle(.bar) : AnyShapeStyle(Color.clear))
                    .animation(.easeInOut(duration: 0.15), value: isScrolled)
            }
            #endif
        }
    }

    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 16) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SheetDesign.contentHorizontalPadding)
            .padding(.bottom, SheetDesign.contentHorizontalPadding)
    }
}

#if os(iOS)
private struct InfoSheetScrollOffset: PreferenceKey {
    static let space = "InfoSheetScroll"
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
#endif

#if os(macOS)
private struct InfoSheetHeaderHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
#endif

struct InfoSheetHeader<Title: View>: View {
    let title: () -> Title
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            title()
                .frame(maxWidth: .infinity, alignment: .leading)
            SheetDoneButton(action: onDismiss)
                .fixedSize()
        }
        .padding(.horizontal, SheetDesign.contentHorizontalPadding)
        .padding(.top, SheetDesign.contentHorizontalPadding)
        .padding(.bottom, 12)
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
