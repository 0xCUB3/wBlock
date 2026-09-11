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
    @State private var showingMetadataEditor = false
    @State private var newSite = ""
    @State private var cachedMetadata = ContentInfoMetadata()
    @State private var cachedByteCount: Int?
    @State private var hasLoadedMetadata = false
    @FocusState private var isSiteFieldFocused: Bool

    private var liveFilter: FilterList {
        filterManager.filterLists.first(where: { $0.id == filter.id }) ?? filter
    }

    private var addableSite: String? {
        guard let normalized = DisabledSitesNormalizer.normalizedDomain(newSite) else { return nil }
        return liveFilter.excludedSites.contains(normalized) ? nil : normalized
    }

    var body: some View {
        Group {
            #if os(macOS)
            InfoContentScrollView { infoContent.padding(20) }
                .frame(width: 460)
            #else
            infoContent.padding(20).infoSheetChromeCompat { dismiss() }
            #endif
        }
        .sheet(isPresented: $showingMetadataEditor) {
            EditCustomFilterView(filterManager: filterManager, filter: liveFilter)
        }
        .task(id: liveFilter.lastUpdated) {
            let snapshot = liveFilter
            let cached = await Task.detached(priority: .userInitiated) { () -> (Int, String)? in
                guard let content = FilterListLoader().readLocalFilterContent(snapshot) else { return nil }
                return (content.utf8.count, String(content.prefix(8192)))
            }.value
            guard !Task.isCancelled else { return }
            cachedByteCount = cached?.0
            cachedMetadata = ContentInfoMetadata.filterHeader(cached?.1 ?? "")
            hasLoadedMetadata = true
        }
    }

    private var infoContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(liveFilter.localizedDisplayName)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if liveFilter.isCustom {
                        Button("Edit") { showingMetadataEditor = true }
                    }
                    #if os(macOS)
                    SheetDoneButton { dismiss() }
                    #endif
                }
                if !liveFilter.localizedDisplayDescription.isEmpty {
                    Text(liveFilter.localizedDisplayDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                ForEach(Array(InfoBadgeSupport.filterBadges(liveFilter, isDownloaded: hasLoadedMetadata ? cachedByteCount != nil : nil).enumerated()), id: \.offset) { _, badge in
                    InfoBadgeView(kind: badge)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                InfoMetadataRow(title: "Type", value: NSLocalizedString("Filters", comment: "Content type"), color: .red)
                InfoMetadataRow(title: "Category", value: liveFilter.category.localizedName)
                if liveFilter.isSelected, let submitted = liveFilter.uniqueRuleCount {
                    InfoMetadataRow(title: "Submitted at last apply", value: submitted.formatted())
                    Text("Submitted counts track source rules sent to the converter, not Safari’s final rule count.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                InfoMetadataRow(title: "Author", value: cachedMetadata.author ?? String(localized: "Not provided"))
                InfoMetadataRow(
                    title: "Homepage",
                    value: cachedMetadata.homepage?.absoluteString ?? String(localized: "Not provided"),
                    url: cachedMetadata.homepage
                )
                if !liveFilter.version.isEmpty { InfoMetadataRow(title: "Version", value: liveFilter.version) }
                if liveFilter.url.scheme?.lowercased() == "http" || liveFilter.url.scheme?.lowercased() == "https" {
                    InfoMetadataRow(title: "Source URL", value: liveFilter.url.absoluteString, url: liveFilter.url)
                    CopyURLButton(url: liveFilter.url)
                }
                if let size = cachedByteCount {
                    InfoMetadataRow(title: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                }
            }
            excludedSitesSection
        }
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
                        #if os(iOS)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        #endif
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
    @State private var editedName = ""
    @State private var editedDescription = ""
    @State private var editedCategory: FilterListCategory = .custom
    @State private var metadataError: String?
    @State private var searchQuery = ""
    @State private var showsSearch = false
    @State private var wrapsLines = false
    @State private var analysis: FilterRuleAnalysis?
    @State private var isLoading = true
    @State private var shownKinds: Set<FilterRuleKind> = Set(FilterRuleKind.allCases)
    /// The lines that pass the View filter, joined, plus a tint per line.
    @State private var displayedRules = ""
    @State private var displayedTints: HighlightLineTints?
    @State private var rebuildTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .caption) private var legendColumnWidth = 160
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let highlightedKinds: [FilterRuleKind] = [.supported, .advanced, .removeParam, .unsupported, .duplicate]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(filter.localizedDisplayName)
                    .font(.headline)
                Spacer()
                SourceViewerControls(wrapsLines: $wrapsLines) { showsSearch.toggle() }
                    .disabled(isLoading)
                if analysis != nil {
                    filterMenu
                }
                if filter.isCustom {
                    Button("Save") {
                        if filterManager.updateCustomFilterList(id: filter.id, name: editedName,
                            category: editedCategory, description: editedDescription) {
                            dismiss()
                        } else { metadataError = filterManager.statusDescription }
                    }
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                SheetDoneButton { dismiss() }
            }
            .padding(16)
            Divider()

            if filter.isCustom {
                AddContentMetadataFields(name: $editedName, description: $editedDescription,
                    category: $editedCategory, categories: FilterListCategory.userListCategories)
                    .padding(16)
                if let metadataError { Text(metadataError).font(.caption).foregroundStyle(.red) }
                Divider()
            }
            if showsSearch {
                HStack {
                    TextField("Search", text: $searchQuery).textFieldStyle(.roundedBorder)
                    Button {
                        searchQuery = ""
                        showsSearch = false
                    } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close search")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
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
                    softTopEdge: true,
                    isLineWrappingEnabled: wrapsLines
                )
                if let analysis {
                    Divider()
                    legend(analysis)
                }
            }
        }
        #if os(macOS)
        .frame(width: 1000, height: 700)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .onAppear {
            editedName = filter.name
            editedDescription = filter.description
            editedCategory = filter.category
        }
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
        .onChangeCompat(of: searchQuery) { _ in rebuildDisplayedText() }
        .onDisappear { rebuildTask?.cancel() }
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
        Group {
            if #available(macOS 13.0, iOS 16.0, *) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        ForEach(Self.highlightedKinds, id: \.self) { kind in
                            legendItem(kind, analysis: analysis)
                                .fixedSize()
                        }
                    }
                    legendGrid(analysis)
                }
            } else {
                legendGrid(analysis)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func legendGrid(_ analysis: FilterRuleAnalysis) -> some View {
        LazyVGrid(
            columns: [GridItem(
                dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: legendColumnWidth),
                alignment: .leading
            )],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(Self.highlightedKinds, id: \.self) { kind in
                legendItem(kind, analysis: analysis)
            }
        }
    }

    private func legendItem(_ kind: FilterRuleKind, analysis: FilterRuleAnalysis) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Self.color(for: kind))
                .frame(width: 8, height: 8)
            Text("\(Self.title(for: kind)): \(analysis.count(of: kind))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Joins the lines that pass the View filter and records which of them
    /// need a category color. The string join runs off the main thread; colour is
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
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = analysis.lines
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) { () -> (String, [Int: FilterRuleKind]) in
                var text = ""
                text.reserveCapacity(lines.reduce(0) { $0 + $1.text.utf8.count + 1 })
                var tinted: [Int: FilterRuleKind] = [:]
                var index = 0
                for line in lines where kinds.contains(line.kind) {
                    if Task.isCancelled { return ("", [:]) }
                    if !query.isEmpty && !line.text.localizedCaseInsensitiveContains(query) { continue }
                    if index > 0 { text.append("\n") }
                    text.append(line.text)
                    tinted[index] = line.kind
                    index += 1
                }
                return (text, tinted)
            }
            let built = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
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
        case .removeParam: return String(localized: "URL Parameters")
        case .unsupported: return String(localized: "Unsupported")
        case .duplicate: return String(localized: "Duplicates")
        }
    }

    private static func symbol(for kind: FilterRuleKind) -> String {
        switch kind {
        case .comment: return "text.quote"
        case .supported: return "checkmark.circle"
        case .advanced: return "curlybraces"
        case .removeParam: return "link.badge.plus"
        case .unsupported: return "xmark.circle"
        case .duplicate: return "doc.on.doc"
        }
    }

    static func color(for kind: FilterRuleKind) -> Color {
        switch kind {
        case .comment: return .secondary
        case .supported: return .green
        case .advanced: return .blue
        case .removeParam: return .teal
        case .unsupported: return .red
        case .duplicate: return .indigo
        }
    }

    #if os(macOS)
    private static func tint(for kind: FilterRuleKind) -> NSColor? {
        switch kind {
        case .advanced: return NSColor.systemBlue
        case .removeParam: return NSColor.systemTeal
        case .unsupported: return NSColor.systemRed
        case .duplicate: return NSColor.systemIndigo
        case .comment: return NSColor.secondaryLabelColor
        case .supported: return NSColor.systemGreen
        }
    }
    #else
    private static func tint(for kind: FilterRuleKind) -> UIColor? {
        switch kind {
        case .advanced: return UIColor.systemBlue
        case .removeParam: return UIColor.systemTeal
        case .unsupported: return UIColor.systemRed
        case .duplicate: return UIColor.systemIndigo
        case .comment: return UIColor.secondaryLabel
        case .supported: return UIColor.systemGreen
        }
    }
    #endif
}
