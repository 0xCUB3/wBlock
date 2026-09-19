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

/// Draws ordinary `Section`s as the full-width material cards the Filters
/// and Userscripts tabs use, so Settings fills the window the same way.
@available(macOS 15.0, *)
struct MacSettingsCardList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Group(sections: content) { sections in
                    ForEach(sections) { section in
                        section.header
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 8)
                        Group(subviews: section.content) { rows in
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                row.macSettingsCardRow(
                                    roundsTop: index == 0,
                                    roundsBottom: index == rows.count - 1
                                )
                            }
                        }
                        section.footer
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .toggleStyle(MacTrailingSwitchToggleStyle())
        .buttonStyle(.plain)
        .labeledContentStyle(MacTrailingLabeledContentStyle())
        .pickerStyle(.menu)
    }
}

/// Keeps the value on the trailing edge, where the grouped Form put it.
struct MacTrailingLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            configuration.content
                .foregroundStyle(.secondary)
        }
    }
}


private extension View {
    func macSettingsCardRow(roundsTop: Bool, roundsBottom: Bool) -> some View {
        frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: MacListCardShape(roundsTop: roundsTop, roundsBottom: roundsBottom))
            .overlay(alignment: .bottom) {
                if !roundsBottom { Divider().padding(.leading, 16) }
            }
            .padding(.horizontal, 16)
    }
}
#endif
