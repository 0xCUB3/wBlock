import SwiftUI

struct CompatibleNavigationStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            NavigationStack(root: content)
        } else {
            #if os(iOS)
            NavigationView(content: content)
                .navigationViewStyle(StackNavigationViewStyle())
            #else
            NavigationView(content: content)
            #endif
        }
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
    func largeSheetPresentationCompat() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
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
