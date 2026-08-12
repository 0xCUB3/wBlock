import SwiftUI
import wBlockCoreService
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct FilterInfoView: View {
    let filter: FilterList

    @Environment(\.dismiss) private var dismiss

    private var isRemote: Bool {
        filter.url.scheme?.lowercased() == "http" || filter.url.scheme?.lowercased() == "https"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(filter.localizedDisplayName)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderless)
            }

            HStack(spacing: 8) {
                Badge(text: "Filters", color: .red)
                if filter.isInlineUserList {
                    Badge(text: "Local Import", color: .blue)
                } else if filter.isCustom {
                    Badge(text: "Custom", color: .blue)
                } else {
                    Badge(text: "Built-in", color: .orange)
                }
            }

            Text(filter.category.localizedName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if !filter.localizedDisplayDescription.isEmpty {
                Text(filter.localizedDisplayDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isRemote {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source URL")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(filter.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = filter.url.absoluteString
                        #elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(filter.url.absoluteString, forType: .string)
                        #endif
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 460, minHeight: 260)
    }
}

struct FilterRulesView: View {
    let filter: FilterList
    @State private var rules = ""
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(filter.localizedDisplayName)
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderless)
            }
            .padding(16)
            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rules.isEmpty {
                Text("No Content Available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MonospacedTextView(
                    text: Binding(get: { rules }, set: { _ in })
                )
            }
        }
        .frame(minWidth: 420, idealWidth: 760, minHeight: 360, idealHeight: 620)
        .task {
            rules = FilterListLoader().readLocalFilterContent(filter) ?? ""
            isLoading = false
        }
    }
}
