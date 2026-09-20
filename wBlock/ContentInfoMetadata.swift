import Foundation
import SwiftUI

nonisolated struct ContentInfoMetadata: Sendable {
    var author: String?
    var homepage: URL?

    static func userscript(_ source: String) -> Self {
        for (start, end) in [("// ==UserScript==", "// ==/UserScript=="), ("==UserStyle==", "==/UserStyle==")] {
            guard let first = source.range(of: start),
                  let last = source.range(of: end, range: first.upperBound..<source.endIndex) else { continue }
            var fields: [String: String] = [:]
            for line in source[first.upperBound..<last.lowerBound].split(whereSeparator: \.isNewline) {
                let clean = line.trimmingCharacters(in: CharacterSet(charactersIn: " /\t*"))
                guard clean.hasPrefix("@") else { continue }
                // Metadata blocks pad values for column alignment, so the
                // remainder after the key still starts with a run of spaces.
                let parts = clean.dropFirst().split(maxSplits: 1, whereSeparator: \.isWhitespace)
                if parts.count == 2 {
                    fields[String(parts[0]).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            return Self(
                author: firstValue(in: fields, keys: ["author"]),
                homepage: webURL(firstValue(in: fields, keys: ["homepageurl", "homepage", "website", "source", "supporturl"]))
            )
        }
        return Self()
    }

    static func filterHeader(_ source: String) -> Self {
        var fields: [String: String] = [:]
        for line in source.split(whereSeparator: \.isNewline) {
            let clean = line.trimmingCharacters(in: .whitespaces)
            guard clean.hasPrefix("!") else { continue }
            let parts = clean.dropFirst().split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                fields[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return Self(
            author: firstValue(in: fields, keys: ["author", "maintainer"]),
            homepage: webURL(firstValue(in: fields, keys: ["homepage", "website", "source", "supporturl"]))
        )
    }

    private static func firstValue(in fields: [String: String], keys: [String]) -> String? {
        for key in keys {
            guard let value = fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    private static func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }
}

/// Copies a URL and briefly swaps its label to a checkmark so the tap is
/// visibly acknowledged.
struct CopyURLButton: View {
    let url: URL
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = url.absoluteString
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            #endif
            withAnimation(.easeInOut(duration: 0.15)) { copied = true }
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.15)) { copied = false }
            }
        } label: {
            if copied {
                Label("Copied", systemImage: "checkmark")
                    .foregroundStyle(.green)
            } else {
                Label("Copy URL", systemImage: "doc.on.doc")
            }
        }
        .buttonStyle(.borderless)
        .animation(.easeInOut(duration: 0.15), value: copied)
        .accessibilityLabel(copied ? Text("Copied") : Text("Copy URL"))
    }
}

enum InfoMetadataValueStyle: Equatable {
    case plain
    case typeBadge
}

struct InfoTypeBadge: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.18))
            )
    }
}

/// A grouped metadata container shared by filter and userscript info views.
struct InfoMetadataList<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        _VariadicView.Tree(Rows()) { content() }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private struct Rows: _VariadicView_UnaryViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            VStack(spacing: 0) {
                ForEach(children) { child in
                    child
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    if child.id != children.last?.id {
                        Divider().padding(.leading, 14).padding(.trailing, 14)
                    }
                }
            }
        }
    }
}

struct InfoMetadataRow: View {
    let title: LocalizedStringKey
    let value: String
    var url: URL? = nil
    var color: Color = .primary
    var valueStyle: InfoMetadataValueStyle = .plain

    private static let inlineValueLimit = 40
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    private var shouldStack: Bool {
        value.count > Self.inlineValueLimit || dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        Group {
            if shouldStack {
                stackedLayout
            } else if #available(macOS 13.0, iOS 16.0, *) {
                ViewThatFits(in: .horizontal) {
                    inlineLayout
                    stackedLayout
                }
            } else {
                stackedLayout
            }
        }
        .font(.callout)
    }

    private var inlineLayout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            titleLabel.fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            valueLabel.fixedSize(horizontal: true, vertical: false)
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleLabel
            valueLabel
        }
    }

    private var titleLabel: some View {
        Text(title)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueLabel: some View {
        Group {
            if let url {
                Button { openURL(url) } label: {
                    Text(verbatim: value)
                        .foregroundStyle(Color.accentColor)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            } else if valueStyle == .typeBadge {
                InfoTypeBadge(text: value)
            } else {
                Text(verbatim: value).foregroundStyle(color)
            }
        }
        .multilineTextAlignment(.leading)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if os(macOS)
private struct InfoContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct InfoContentScrollView<Content: View>: View {
    var maximumHeight: CGFloat = 640
    @ViewBuilder var content: () -> Content
    @State private var contentHeight: CGFloat = 360

    var body: some View {
        ScrollView {
            content().background(GeometryReader { proxy in
                Color.clear.preference(key: InfoContentHeight.self, value: proxy.size.height)
            })
        }
        .frame(height: min(contentHeight, maximumHeight))
        .onPreferenceChange(InfoContentHeight.self) { height in
            if height > 0 { contentHeight = height }
        }
    }
}
#endif
