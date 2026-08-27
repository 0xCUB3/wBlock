import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
struct ApplySheetGlassBackgroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.presentationBackground {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: Rectangle())
                    .ignoresSafeArea()
            }
        } else if #available(iOS 16.4, *) {
            content.presentationBackground(.regularMaterial)
        } else {
            content
        }
    }
}
#endif

struct CompatibleNavigationStack<Content: View>: View {
    /// Pre-Tahoe non-navigation tabs must not own stacks because SwiftUI can
    /// duplicate their window toolbar contributions after closing panels.
    let requiresNavigationView: Bool
    @ViewBuilder var content: () -> Content

    init(requiresNavigationView: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.requiresNavigationView = requiresNavigationView
        self.content = content
    }

    var body: some View {
        #if os(macOS)
        if !requiresNavigationView {
            if #unavailable(macOS 26.0) {
                content()
            } else {
                NavigationStack(root: content)
            }
        } else if #available(macOS 13.0, *) {
            NavigationStack(root: content)
        } else {
            NavigationView(content: content)
        }
        #else
        if #available(iOS 16.0, *) {
            NavigationStack(root: content)
        } else {
            NavigationView(content: content)
                .navigationViewStyle(StackNavigationViewStyle())
        }
        #endif
    }
}

private struct OnChangeCompatModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (_ oldValue: Value, _ newValue: Value) -> Void

    @State private var previousValue: Value

    init(
        value: Value,
        action: @escaping (_ oldValue: Value, _ newValue: Value) -> Void
    ) {
        self.value = value
        self.action = action
        _previousValue = State(initialValue: value)
    }

    func body(content: Content) -> some View {
        content.onChange(of: value) { newValue in
            let oldValue = previousValue
            previousValue = newValue
            action(oldValue, newValue)
        }
    }
}

extension View {
    @ViewBuilder
    func onChangeCompat<Value: Equatable>(
        of value: Value,
        perform action: @escaping (_ oldValue: Value, _ newValue: Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            onChange(of: value, action)
        } else {
            modifier(OnChangeCompatModifier(value: value, action: action))
        }
    }

    @ViewBuilder
    func onChangeCompat<Value: Equatable>(
        of value: Value,
        perform action: @escaping (_ newValue: Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            onChange(of: value, perform: action)
        }
    }

    @ViewBuilder
    func searchableCompat(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        prompt: LocalizedStringKey
    ) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            searchable(text: text, isPresented: isPresented, prompt: prompt)
        } else {
            searchable(text: text, prompt: prompt)
        }
    }

    @ViewBuilder
    func scrollBounceBasedOnSizeCompat() -> some View {
        if #available(iOS 16.4, macOS 13.3, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }

    @ViewBuilder
    func largeSheetPresentationCompat() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }

    @ViewBuilder
    func applySheetPresentationCompat(prefersLarge: Bool, prefersTall: Bool = false) -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            #if os(iOS)
            applySheetDetentsCompat(prefersLarge: prefersLarge, prefersTall: prefersTall)
                .modifier(ApplySheetGlassBackgroundModifier())
            #else
            applySheetDetentsCompat(prefersLarge: prefersLarge, prefersTall: prefersTall)
            #endif
        } else {
            self
        }
    }

    @available(iOS 16.0, macOS 13.0, *)
    @ViewBuilder
    private func applySheetDetentsCompat(prefersLarge: Bool, prefersTall: Bool) -> some View {
        if prefersLarge {
            presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else if prefersTall {
            presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
        } else {
            presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    func glassButtonStyleCompat() -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.borderless)
        }
        #else
        buttonStyle(.borderless)
        #endif
    }

    @ViewBuilder
    func groupedFormStyleCompat() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            formStyle(.grouped)
        } else {
            self
        }
    }

    @ViewBuilder
    func hiddenListRowSeparatorCompat() -> some View {
        if #available(iOS 15.0, macOS 13.0, *) {
            listRowSeparator(.hidden)
        } else {
            self
        }
    }
}

struct CompatibleLabeledContent<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            LabeledContent {
                content
            } label: {
                label
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                label
                Spacer(minLength: 12)
                content
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

extension CompatibleLabeledContent where Label == Text, Content == Text {
    init(_ titleKey: LocalizedStringKey, value: String) {
        self.init {
            Text(value)
        } label: {
            Text(titleKey)
        }
    }

    init(_ title: String, value: String) {
        self.init {
            Text(value)
        } label: {
            Text(title)
        }
    }
}

extension CompatibleLabeledContent where Label == Text {
    init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.init(content: content) {
            Text(titleKey)
        }
    }
}

extension AnyTransition {
    static var blurReplaceCompat: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.98))
    }
}

/// Tracks a 3s press without @State updates that would reset the drag gesture.
private final class ApplyChangesHoldTracker {
    var didBegin = false
    var isPressing = false
    var task: Task<Void, Never>?

    func start(isDisabled: Bool, onFire: @escaping () -> Void) {
        guard !isDisabled else { return }
        cancel()
        isPressing = true
        task = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !Task.isCancelled, self.isPressing else { return }
                onFire()
            }
        }
    }

    func cancel() {
        isPressing = false
        task?.cancel()
        task = nil
    }

    func reset() {
        cancel()
        didBegin = false
    }
}

/// Toolbar Apply control: tap checks for updates, 3s hold force-applies.
struct ApplyChangesHoldButton<Label: View>: View {
    let isDisabled: Bool
    let hasPendingChanges: Bool
    let onTap: () -> Void
    let onForceApply: () -> Void
    let label: Label

    @State private var lastForceApplyAt: Date?
    @State private var hold = ApplyChangesHoldTracker()

    init(
        isDisabled: Bool,
        hasPendingChanges: Bool,
        onTap: @escaping () -> Void,
        onForceApply: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.isDisabled = isDisabled
        self.hasPendingChanges = hasPendingChanges
        self.onTap = onTap
        self.onForceApply = onForceApply
        self.label = label()
    }

    var body: some View {
        Button(action: handleTap) {
            label
        }
        .disabled(isDisabled)
        .accessibilityLabel("Apply Changes")
        .accessibilityHint("Hold for 3 seconds to apply without checking for updates.")
        .help(helpText)
        .simultaneousGesture(forceApplyHoldGesture)
        .onChangeCompat(of: isDisabled) { disabled in
            if disabled {
                hold.cancel()
            }
        }
    }

    private var helpText: String {
        let action = hasPendingChanges
            ? String(localized: "Apply your pending changes")
            : String(localized: "Apply changes")
        return action
            + " "
            + String(localized: "Hold for 3 seconds to apply without checking for updates.")
    }

    private var forceApplyHoldGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !hold.didBegin {
                    hold.didBegin = true
                    hold.start(isDisabled: isDisabled) {
                        handleForceApply()
                    }
                }
                let distance = hypot(value.translation.width, value.translation.height)
                if distance > 80 {
                    hold.cancel()
                }
            }
            .onEnded { _ in
                hold.reset()
            }
    }

    private func handleTap() {
        guard !isDisabled else { return }
        if let lastForceApplyAt, Date().timeIntervalSince(lastForceApplyAt) < 1 {
            return
        }
        onTap()
    }

    private func handleForceApply() {
        guard !isDisabled else { return }
        if let lastForceApplyAt, Date().timeIntervalSince(lastForceApplyAt) < 1 {
            return
        }
        lastForceApplyAt = Date()
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        onForceApply()
    }
}
