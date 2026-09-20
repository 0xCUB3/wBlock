import SwiftUI

/// Row metadata shared by the filter and userscript lists.
enum ContentRowMetadata {
    /// Joins the non-empty parts with a middle dot so every row spends one
    /// caption line on counts, version, and update time.
    static func summary(_ parts: [String?]) -> String {
        parts.compactMap { part in
            guard let part = part?.trimmingCharacters(in: .whitespacesAndNewlines), !part.isEmpty else { return nil }
            return part
        }
        .joined(separator: " · ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.dateTimeStyle = .named
        return f
    }()

    /// "Updated 2 hr. ago". Rows get the short form; the Info sheet keeps the
    /// full timestamp.
    static func updatedLabel(_ date: Date?) -> String? {
        guard let date else { return nil }
        return LocalizedStrings.format(
            "Updated %@", comment: "Row label for a relative last-updated time",
            relativeFormatter.localizedString(for: date, relativeTo: Date())
        )
    }

    /// "Version 1.2" or nil when the version is missing or the placeholder
    /// the updater writes when a list declares none.
    static func versionLabel(_ version: String) -> String? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("Unknown") != .orderedSame else { return nil }
        return LocalizedStrings.format("Version %@", comment: "Content version label", trimmed)
    }
}

#if os(iOS)
/// Secondary actions at the bottom of an iOS Info sheet. macOS keeps these in
/// the row's context menu, so the list only exists on iOS.
struct InfoActionList<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        _VariadicView.Tree(Rows()) { content() }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 4)
    }

    /// Separators go between rows only, so the last row meets the rounded edge.
    private struct Rows: _VariadicView_UnaryViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            VStack(spacing: 0) {
                ForEach(children) { child in
                    child
                    if child.id != children.last?.id {
                        Divider().padding(.leading, 48)
                    }
                }
            }
        }
    }
}

struct InfoActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 22)
                Text(title)
                Spacer()
                if role != .destructive {
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(role == .destructive ? Color.red : Color.accentColor)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct InfoCategoryRow<Category: Hashable & Identifiable>: View {
    @Binding var selection: Category
    let categories: [Category]
    let name: (Category) -> String

    var body: some View {
        Menu {
            Picker("Move to", selection: $selection) {
                ForEach(categories) { category in
                    Text(name(category)).tag(category)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .frame(width: 22)
                Text("Move to")
                Spacer()
                Text(name(selection))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
