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
        // The native glass X on both platforms; macOS drew a filled circle
        // beside its glass source controls (#1089).
        if #available(iOS 26.0, macOS 26.0, *) {
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
        .opaqueSheetBackgroundCompat()
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

    init(@ViewBuilder header: @escaping () -> Header, @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            header()
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                scrollContent
                    #if os(iOS)
                    .padding(.top, 4)
                    #endif
            }
            .scrollBounceBasedOnSizeCompat()
            // An inset reserves space but still lets rows draw behind the
            // header. Keep the viewport below it, including Duo's side bars.
            .clipped()
        }
        #if os(macOS)
        .infoPopoverHeightCap()
        #else
        .opaqueSheetBackgroundCompat()
        #endif
    }

    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 16) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SheetDesign.contentHorizontalPadding)
            .padding(.bottom, SheetDesign.contentHorizontalPadding)
    }
}

#if os(iOS)
extension View {
    /// iPad form sheets are glass on iOS 26, so the green toggles beneath tinted
    /// them in dark mode, and their text flashed from gray to its real color as
    /// the glass settled (cameren, Discord). Match the opaque iPhone sheet.
    @ViewBuilder
    func opaqueSheetBackgroundCompat() -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(Color(uiColor: .systemBackground))
        } else {
            self
        }
    }

    /// Presents filter and userscript info sheets at medium height first, then
    /// expands to large on drag or tap to reveal full details and actions (#1168).
    @ViewBuilder
    func expandableInfoSheetPresentationCompat(isExpanded: Binding<Bool>) -> some View {
        if #available(iOS 16.0, *) {
            modifier(ExpandableInfoSheetDetentsModifier(isExpanded: isExpanded))
        } else {
            self
        }
    }
}

@available(iOS 16.0, *)
private struct ExpandableInfoSheetDetentsModifier: ViewModifier {
    @Binding var isExpanded: Bool
    @State private var selectedDetent: PresentationDetent = .medium
    @State private var allowsDetentGestureExpand = false

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 16.4, *) {
                content
                    .presentationContentInteraction(isExpanded ? .scrolls : .resizes)
            } else {
                content
            }
        }
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .onAppear {
            allowsDetentGestureExpand = false
            let initial: PresentationDetent = isExpanded ? .large : .medium
            if selectedDetent != initial {
                selectedDetent = initial
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                allowsDetentGestureExpand = true
            }
        }
        .onChangeCompat(of: isExpanded) { _, expanded in
            let target: PresentationDetent = expanded ? .large : .medium
            if selectedDetent != target {
                selectedDetent = target
            }
        }
        .onChangeCompat(of: selectedDetent) { _, detent in
            if detent == .large, !isExpanded {
                guard allowsDetentGestureExpand else {
                    selectedDetent = .medium
                    return
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isExpanded = true
                }
            } else if detent == .medium, isExpanded {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isExpanded = false
                }
            }
        }
    }
}

/// Compact prompt shown at medium detent to reveal full metadata and actions.
struct InfoSheetExpandButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            HStack {
                Text("More Details & Actions")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.groupFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
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
    let title: Text
    let isLoading: Bool
    let onDismiss: () -> Void

    init(title: String, isLoading: Bool = false, onDismiss: @escaping () -> Void) {
        self.init(Text(LocalizedStringKey(title)), isLoading: isLoading, onDismiss: onDismiss)
    }

    /// For user-supplied names, which must not be read as keys or Markdown.
    init(verbatim title: String, isLoading: Bool = false, onDismiss: @escaping () -> Void) {
        self.init(Text(verbatim: title), isLoading: isLoading, onDismiss: onDismiss)
    }

    private init(_ title: Text, isLoading: Bool, onDismiss: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack {
            title
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(1)
            Spacer()
            dismissControl
                .disabled(isLoading)
                .opacity(isLoading ? 0 : 1)
                .accessibilityHidden(isLoading)
                .transaction { $0.animation = nil }
        }
        .padding(.horizontal, SheetDesign.contentHorizontalPadding)
        .padding(.top, SheetDesign.contentHorizontalPadding)
        // Keeps the form's edge off the title and X, like InfoSheetHeader (Strawberry, Discord).
        .padding(.bottom, 12)
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
        .padding(.horizontal, SheetDesign.contentHorizontalPadding)
        .padding(.vertical, 12)
        .background(Color.clear)
    }
}

// MARK: - Sheet Container

enum SheetFill {
    /// Form-style sheets: gray grouped canvas with inset white cards.
    case grouped
    /// Apply Changes-style sheets: one continuous systemBackground card.
    case system
    /// No opaque fill — system sheet chrome (liquid glass) shows through.
    case clear
}

struct SheetContainer<Content: View>: View {
    typealias Fill = SheetFill

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
    /// Large on iOS. macOS keeps the regular size, which draws a rounded
    /// rectangle like its other buttons; large ones are capsules (#1092).
    func primaryActionButtonStyle() -> some View {
        #if os(iOS)
        self.buttonStyle(.borderedProminent).controlSize(.large)
        #else
        self.buttonStyle(.borderedProminent)
        #endif
    }
}
