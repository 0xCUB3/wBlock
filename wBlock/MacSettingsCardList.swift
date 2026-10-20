#if os(macOS)
import SwiftUI

/// A switch pinned to the trailing edge of its row, the layout a grouped Form
/// gives toggles for free and a plain List does not.
struct MacTrailingSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

#endif
