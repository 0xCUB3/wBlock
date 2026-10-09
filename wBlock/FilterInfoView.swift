import SwiftUI
import wBlockCoreService

struct FilterInfoView: View {
    let filter: FilterList
    @ObservedObject var filterManager: AppFilterManager
    var onChangeCategory: ((FilterListCategory) -> Void)? = nil
    var isDownloading = false
    /// Returns false when the download waits on a confirmation shown from this sheet.
    var onDownload: (() -> Bool)? = nil
    /// Presents an action's sheet from the window instead of this view. A
    /// macOS popover would otherwise anchor the sheet to itself (#923).
    var onAction: ((FilterContextMenuAction) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showingMetadataEditor = false
    @State private var showingSettings = false
    @State private var showingRules = false
    @State private var confirmingDelete = false
    @State private var cachedMetadata = ContentInfoMetadata()
    @State private var cachedByteCount: Int?

    private var isDownloaded: Bool { filterManager.loader.filterFileExists(liveFilter) }

    private var liveFilter: FilterList {
        filterManager.filterLists.first(where: { $0.id == filter.id }) ?? filter
    }

    var body: some View {
        Group {
            InfoSheetContainer {
                InfoSheetHeader {
                    Text(liveFilter.localizedDisplayName)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } onDismiss: { dismiss() }
            } content: {
                infoContent
            }
            #if os(macOS)
            .frame(width: 460)
            #endif
        }
        .sheet(isPresented: $showingMetadataEditor) {
            EditCustomFilterView(filterManager: filterManager, filter: liveFilter)
        }
        .sheet(isPresented: $showingSettings) {
            FilterSettingsView(filter: liveFilter, filterManager: filterManager)
                .infoSheetPresentationCompat()
        }
        .sheet(isPresented: $showingRules) {
            if liveFilter.isInlineUserList {
                EditUserListView(filterManager: filterManager, filter: liveFilter)
            } else {
                FilterRulesView(filter: liveFilter, filterManager: filterManager)
            }
        }
        .onAppear(perform: loadLocalHeader)
        .onChangeCompat(of: liveFilter.lastUpdated) { _ in loadLocalHeader() }
    }

    /// Read before the first frame: rows that arrive after the popover opens
    /// resize it mid-animation, and AppKit slides it diagonally to refit.
    private func loadLocalHeader() {
        let local = FilterListLoader().localFilterHeader(liveFilter)
        cachedByteCount = local?.size
        cachedMetadata = ContentInfoMetadata.filterHeader(local?.header ?? "")
    }

    private func perform(_ action: FilterContextMenuAction, locally: () -> Void) {
        guard let onAction else { return locally() }
        dismiss()
        onAction(action)
    }

    private var infoContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if !liveFilter.localizedDisplayDescription.isEmpty {
                    Text(liveFilter.localizedDisplayDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    ForEach(Array(InfoBadgeSupport.filterBadges(liveFilter, isDownloaded: isDownloaded).enumerated()), id: \.offset) { _, badge in
                        InfoBadgeView(kind: badge)
                    }
                }
            }
            InfoMetadataList {
                InfoMetadataRow(title: "Type", value: NSLocalizedString("Filters", comment: "Content type"), valueStyle: .typeBadge)
                if liveFilter.isSelected, let submitted = liveFilter.uniqueRuleCount {
                    VStack(alignment: .leading, spacing: 2) {
                        InfoMetadataRow(title: "Source Rules", value: submitted.formatted())
                        Text("Source rules submitted to the converter at last apply, not Safari’s final rule count.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                InfoMetadataRow(title: "Author", value: cachedMetadata.author ?? String(localized: "Not provided"))
                InfoMetadataRow(
                    title: "Homepage",
                    value: cachedMetadata.homepage?.absoluteString ?? String(localized: "Not provided"),
                    url: cachedMetadata.homepage
                )
                if isDownloaded, !liveFilter.version.isEmpty { InfoMetadataRow(title: "Version", value: liveFilter.version) }
                if liveFilter.url.scheme?.lowercased() == "http" || liveFilter.url.scheme?.lowercased() == "https" {
                    VStack(alignment: .leading, spacing: 6) {
                        InfoMetadataRow(title: "Source URL", value: liveFilter.url.absoluteString, url: liveFilter.url)
                        HStack {
                            CopyURLButton(url: liveFilter.url)
                            FilterFallbacksButton(
                                filter: liveFilter,
                                onShow: onAction.map { _ in { perform(.fallbacks) {} } }
                            )
                        }
                    }
                }
                if let size = cachedByteCount {
                    InfoMetadataRow(title: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                }
            }
            actionList
        }
    }

    private var actionList: some View {
        let actions = ContextMenuActionAvailability.filterActions(for: liveFilter, isDownloaded: isDownloaded)
        return InfoActionList {
            if actions.contains(.download), let onDownload {
                Button {
                    if onDownload() { dismiss() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle").frame(width: 22)
                        if isDownloading {
                            Text("Downloading…")
                            Spacer()
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Download")
                            Spacer()
                            Image(systemName: "chevron.forward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDownloading)
            }
            if actions.contains(.settings) {
                InfoActionRow("Settings", systemImage: "gearshape") { perform(.settings) { showingSettings = true } }
            }
            if actions.contains(.viewRules) {
                InfoActionRow("View Rules", systemImage: "doc.text") { perform(.viewRules) { showingRules = true } }
            }
            if actions.contains(.editRules) {
                InfoActionRow("Edit Rules", systemImage: "pencil") { perform(.editRules) { showingRules = true } }
            }
            if actions.contains(.editInfo) {
                InfoActionRow("Edit Info", systemImage: "square.and.pencil") { perform(.editInfo) { showingMetadataEditor = true } }
            }
            if actions.contains(.moveTo), let onChangeCategory {
                InfoCategoryRow(
                    selection: Binding(get: { liveFilter.category }, set: onChangeCategory),
                    categories: FilterListCategory.moveTargets,
                    name: { $0.localizedName }
                )
            }
            if actions.contains(.deleteList) {
                InfoActionRow("Delete Added List", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    // Anchored to the row so the iPad popover arrow points at it.
                    .confirmationDialog("Delete Added List", isPresented: $confirmingDelete, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            filterManager.removeFilterList(liveFilter)
                            dismiss()
                        }
                    }
            }
        }
    }

}

struct FilterSettingsView: View {
    let filter: FilterList
    @ObservedObject var filterManager: AppFilterManager

    private var liveFilter: FilterList {
        filterManager.filterLists.first(where: { $0.id == filter.id }) ?? filter
    }

    var body: some View {
        ContentSettingsView(name: liveFilter.localizedDisplayName) {
            if liveFilter.isRemoteURL {
                AutomaticUpdatesToggle(
                    isOn: liveFilter.updatesAutomatically,
                    description: "Turn this off to keep the current version when wBlock updates filter lists in bulk or on a schedule."
                ) { filterManager.setFilterList(liveFilter.id, updatesAutomatically: $0) }
            }
            SiteScopeEditor(
                title: "Apply on", selectedSites: liveFilter.selectedSites, excludedSites: liveFilter.excludedSites,
                emptySelectionMessage: "No sites selected. This list will not apply.",
                excludedMessage: "This list will not apply on these sites. Other lists still apply.",
                footer: "Sites include their subdomains. Apply changes to update filtering.",
                updateSelected: { filterManager.setSelectedSites($0, for: liveFilter.id) },
                updateExcluded: { filterManager.setExcludedSites($0, for: liveFilter.id) }
            )
        }
    }
}

struct FilterRulesView: View {
    let filter: FilterList
    @ObservedObject var filterManager: AppFilterManager
    @State private var rules = ""
    @StateObject private var editorController = CodeMirrorEditorController(text: "")
    @State private var wrapsLines = false
    @State private var analysis: FilterRuleAnalysis?
    @State private var isLoading = true
    @State private var shownKinds: Set<FilterRuleKind> = Set(FilterRuleKind.allCases)
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
                SourceViewerControls(wrapsLines: $wrapsLines, onSearch: editorController.openSearch) {
                    if analysis != nil { filterMenu }
                }
                .disabled(isLoading)
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
                CodeMirrorTextEditor(
                    controller: editorController,
                    isEditable: false,
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
        .sourceSheetPresentationCompat()
        #endif
        .task {
            rules = FilterListLoader().readLocalFilterContent(filter) ?? ""
            editorController.replaceText(rules, lineKinds: [:], markClean: true)
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
            // The chevron marks it as a menu and keeps it apart from Wrap Lines'
            // similar bars (#948); tinted while some kinds are hidden.
            HStack(spacing: 2) {
                Image(systemName: "line.3.horizontal.decrease")
                #if os(iOS)
                // macOS draws its own indicator and drops extra label images.
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                #endif
            }
            .frame(height: SourceControlMetrics.size)
            .contentShape(Rectangle())
            .foregroundStyle(shownKinds.count == FilterRuleKind.allCases.count ? Color.primary : Color.accentColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .menuStaysOpenCompat()
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("View")
        .help("View")
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

    /// Joins the lines selected by the View menu off the main thread, then
    /// replaces the read-only CodeMirror document and its visible line classes.
    /// CodeMirror owns text search so filter viewing has the same Find/next/previous
    /// behavior as userscripts.
    private func rebuildDisplayedText() {
        rebuildTask?.cancel()
        guard let analysis else {
            editorController.replaceText(rules, lineKinds: [:], markClean: true)
            return
        }
        let kinds = shownKinds
        let lines = analysis.lines
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let worker = Task.detached(priority: .userInitiated) { () -> (String, [Int: String]) in
                var text = ""
                var lineKinds: [Int: String] = [:]
                text.reserveCapacity(lines.reduce(0) { $0 + $1.text.utf8.count + 1 })
                var index = 0
                for line in lines where kinds.contains(line.kind) {
                    if Task.isCancelled { return ("", [:]) }
                    if index > 0 { text.append("\n") }
                    text.append(line.text)
                    lineKinds[index] = line.kind.rawValue
                    index += 1
                }
                return (text, lineKinds)
            }
            let built = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            editorController.replaceText(built.0, lineKinds: built.1, markClean: true)
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

}
