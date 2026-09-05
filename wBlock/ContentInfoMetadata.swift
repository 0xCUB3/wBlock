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
                let parts = clean.dropFirst().split(maxSplits: 1, whereSeparator: \.isWhitespace)
                if parts.count == 2 { fields[String(parts[0]).lowercased()] = String(parts[1]) }
            }
            return Self(author: fields["author"], homepage: webURL(fields["homepageurl"] ?? fields["homepage"]))
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
        return Self(author: fields["author"] ?? fields["maintainer"], homepage: webURL(fields["homepage"]))
    }

    private static func webURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }
}

struct InfoMetadataRow: View {
    let title: LocalizedStringKey
    let value: String
    var url: URL? = nil
    var color: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            HStack(spacing: 0) { Text(title); Text(verbatim: ":") }
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Group {
                if let url {
                    Link(value, destination: url)
                } else {
                    Text(verbatim: value).foregroundStyle(color)
                }
            }
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }
}

#if os(macOS)
private struct InfoContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct InfoContentScrollView<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var contentHeight: CGFloat = 360

    var body: some View {
        ScrollView {
            content().background(GeometryReader { proxy in
                Color.clear.preference(key: InfoContentHeight.self, value: proxy.size.height)
            })
        }
        .frame(height: min(contentHeight, 640))
        .onPreferenceChange(InfoContentHeight.self) { height in
            if height > 0 { contentHeight = height }
        }
    }
}
#endif
