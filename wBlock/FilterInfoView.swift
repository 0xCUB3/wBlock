import SwiftUI
import wBlockCoreService
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct FilterInfoView: View {
    let filter: FilterList
    @ObservedObject var filterManager: AppFilterManager

    @Environment(\.dismiss) private var dismiss
    @State private var newSite = ""
    @FocusState private var isSiteFieldFocused: Bool

    private var liveFilter: FilterList {
        filterManager.filterLists.first(where: { $0.id == filter.id }) ?? filter
    }

    private var addableSite: String? {
        guard let normalized = DisabledSitesNormalizer.normalizedDomain(newSite) else { return nil }
        return liveFilter.excludedSites.contains(normalized) ? nil : normalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(liveFilter.localizedDisplayName)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                #if os(macOS)
                Spacer()
                SheetDoneButton { dismiss() }
                #endif
            }

            HStack(spacing: 8) {
                ForEach(Array(InfoBadgeSupport.filterBadges(liveFilter).enumerated()), id: \.offset) { _, badge in
                    InfoBadgeView(kind: badge)
                }
            }

            Text(liveFilter.category.localizedName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            if !liveFilter.localizedDisplayDescription.isEmpty {
                Text(liveFilter.localizedDisplayDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if liveFilter.url.scheme?.lowercased() == "http" || liveFilter.url.scheme?.lowercased() == "https" {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source URL")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(liveFilter.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = liveFilter.url.absoluteString
                        #elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(liveFilter.url.absoluteString, forType: .string)
                        #endif
                    } label: {
                        Label("Copy URL", systemImage: "doc.on.doc")
                    }
                }
            }

            excludedSitesSection

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 460, minHeight: 320)
        .infoSheetChromeCompat { dismiss() }
    }

    private var excludedSitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStrings.text("Excluded Sites", comment: "Per-list site exclusion heading"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Text(LocalizedStrings.text(
                "This list will not apply on these sites. Other lists still apply.",
                comment: "Per-list site exclusion explanation"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                TextField("example.com", text: $newSite)
                    .textFieldStyle(.plain)
                    .focused($isSiteFieldFocused)
                    .onSubmit { addExcludedSite() }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    addExcludedSite()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(addableSite == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                }
                .buttonStyle(.plain)
                .noFocusRingCompat()
                .disabled(addableSite == nil)
            }

            ForEach(liveFilter.excludedSites, id: \.self) { site in
                HStack {
                    Text(site)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        removeExcludedSite(site)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .noFocusRingCompat()
                    .accessibilityLabel(LocalizedStrings.text("Remove", comment: "Remove excluded site"))
                }
            }
        }
    }

    private func addExcludedSite() {
        guard let site = addableSite else { return }
        filterManager.setExcludedSites(liveFilter.excludedSites + [site], for: liveFilter.id)
        newSite = ""
        isSiteFieldFocused = true
    }

    private func removeExcludedSite(_ site: String) {
        filterManager.setExcludedSites(liveFilter.excludedSites.filter { $0 != site }, for: liveFilter.id)
    }
}

struct FilterRulesView: View {
    let filter: FilterList
    @ObservedObject var filterManager: AppFilterManager
    @State private var rules = ""
    @State private var analysis: FilterRuleAnalysis?
    @State private var isLoading = true
    @State private var shownKinds: Set<FilterRuleKind> = Set(FilterRuleKind.allCases)
    /// The lines that pass the View filter, joined, plus a tint per line.
    @State private var displayedRules = ""
    @State private var displayedTints: HighlightLineTints?
    @State private var rebuildTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private static let highlightedKinds: [FilterRuleKind] = [.supported, .advanced, .unsupported, .duplicate]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(filter.localizedDisplayName)
                    .font(.headline)
                Spacer()
                if analysis != nil {
                    filterMenu
                }
                SheetDoneButton { dismiss() }
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
                    text: Binding(get: { displayedRules }, set: { _ in }),
                    lineTints: displayedTints,
                    softTopEdge: true
                )
                if let analysis {
                    Divider()
                    legend(analysis)
                }
            }
        }
        .frame(minWidth: 420, idealWidth: 760, minHeight: 360, idealHeight: 620)
        .task {
            rules = FilterListLoader().readLocalFilterContent(filter) ?? ""
            displayedRules = rules
            isLoading = false
            guard !rules.isEmpty else { return }
            let content = rules
            let earlier = earlierListContents()
            let result = await Task.detached(priority: .userInitiated) { () -> FilterRuleAnalysis in
                var seen = Set<String>()
                for text in earlier { seen.formUnion(FilterRuleAnalysis.ruleSet(from: text)) }
                return FilterRuleAnalysis.analyze(
                    content: content,
                    seenInEarlierLists: seen,
                    isCancelled: { Task.isCancelled }
                )
            }.value
            if !result.lines.isEmpty {
                analysis = result
                rebuildDisplayedText()
            }
        }
        .onChangeCompat(of: shownKinds) { _ in rebuildDisplayedText() }
    }

    /// Contents of enabled lists that compile before this one, so a rule the
    /// engine already has from another list shows as a duplicate here.
    private func earlierListContents() -> [String] {
        let selected = filterManager.filterLists.filter { $0.isSelected }
        let ordered = ContentBlockerMappingService.orderedForCompilation(selected)
        guard let index = ordered.firstIndex(where: { $0.id == filter.id }) else { return [] }
        let loader = FilterListLoader()
        return ordered[..<index].compactMap { loader.readLocalFilterContent($0) }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(Self.highlightedKinds, id: \.self) { kind in
                Toggle(isOn: Binding(
                    get: { shownKinds.contains(kind) },
                    set: { on in
                        if on { shownKinds.insert(kind) } else { shownKinds.remove(kind) }
                    }
                )) {
                    Label(Self.title(for: kind), systemImage: Self.symbol(for: kind))
                }
            }
            Divider()
            Toggle(isOn: Binding(
                get: { shownKinds.contains(.comment) },
                set: { on in
                    if on { shownKinds.insert(.comment) } else { shownKinds.remove(.comment) }
                }
            )) {
                Label("Comments", systemImage: "text.quote")
            }
        } label: {
            Label("View", systemImage: shownKinds.count == FilterRuleKind.allCases.count
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func legend(_ analysis: FilterRuleAnalysis) -> some View {
        HStack(spacing: 14) {
            ForEach(Self.highlightedKinds, id: \.self) { kind in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Self.color(for: kind))
                        .frame(width: 8, height: 8)
                    Text("\(Self.title(for: kind)): \(analysis.count(of: kind))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Joins the lines that pass the View filter and records which of them
    /// need a tint. The string join runs off the main thread; syntax colour is
    /// applied per viewport by MonospacedTextView, so a multi-megabyte list
    /// never builds one huge attributed string (that froze iPhones).
    private func rebuildDisplayedText() {
        rebuildTask?.cancel()
        guard let analysis else {
            displayedRules = rules
            displayedTints = nil
            return
        }
        let kinds = shownKinds
        let lines = analysis.lines
        rebuildTask = Task {
            let built = await Task.detached(priority: .userInitiated) { () -> (String, [Int: FilterRuleKind]) in
                var text = ""
                text.reserveCapacity(lines.reduce(0) { $0 + $1.text.utf8.count + 1 })
                var tinted: [Int: FilterRuleKind] = [:]
                var index = 0
                for line in lines where kinds.contains(line.kind) {
                    if Task.isCancelled { return ("", [:]) }
                    if index > 0 { text.append("\n") }
                    text.append(line.text)
                    if line.kind == .advanced || line.kind == .unsupported || line.kind == .duplicate {
                        tinted[index] = line.kind
                    }
                    index += 1
                }
                return (text, tinted)
            }.value
            guard !Task.isCancelled else { return }
            var tints: HighlightLineTints = [:]
            tints.reserveCapacity(built.1.count)
            for (index, kind) in built.1 {
                if let tint = Self.tint(for: kind) { tints[index] = tint }
            }
            displayedRules = built.0
            displayedTints = tints
        }
    }

    static func title(for kind: FilterRuleKind) -> String {
        switch kind {
        case .comment: return String(localized: "Comments")
        case .supported: return String(localized: "Supported")
        case .advanced: return String(localized: "Needs wBlock Scripts")
        case .unsupported: return String(localized: "Unsupported")
        case .duplicate: return String(localized: "Duplicates")
        }
    }

    private static func symbol(for kind: FilterRuleKind) -> String {
        switch kind {
        case .comment: return "text.quote"
        case .supported: return "checkmark.circle"
        case .advanced: return "curlybraces"
        case .unsupported: return "xmark.circle"
        case .duplicate: return "doc.on.doc"
        }
    }

    static func color(for kind: FilterRuleKind) -> Color {
        switch kind {
        case .comment: return .secondary
        case .supported: return .green
        case .advanced: return .blue
        case .unsupported: return .red
        case .duplicate: return .orange
        }
    }

    #if os(macOS)
    private static func tint(for kind: FilterRuleKind) -> NSColor? {
        switch kind {
        case .advanced: return NSColor.systemBlue.withAlphaComponent(0.18)
        case .unsupported: return NSColor.systemRed.withAlphaComponent(0.22)
        case .duplicate: return NSColor.systemOrange.withAlphaComponent(0.22)
        case .comment, .supported: return nil
        }
    }
    #else
    private static func tint(for kind: FilterRuleKind) -> UIColor? {
        switch kind {
        case .advanced: return UIColor.systemBlue.withAlphaComponent(0.18)
        case .unsupported: return UIColor.systemRed.withAlphaComponent(0.22)
        case .duplicate: return UIColor.systemOrange.withAlphaComponent(0.22)
        case .comment, .supported: return nil
        }
    }
    #endif
}
