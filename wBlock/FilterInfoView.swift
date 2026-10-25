import SwiftUI
import wBlockCoreService

struct FilterInfoView: View {
    let filter: FilterList
    @ObservedObject var filterManager: AppFilterManager
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
    @State private var showingFallbacks = false
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
        // From the view's root like the other sheets: attached to the row's
        // button, the sheet's X sometimes did nothing on iOS (#999).
        .sheet(isPresented: $showingFallbacks) {
            FilterFallbacksView(filter: liveFilter, urls: FilterListURLMirror.fallbackURLs(for: liveFilter.url))
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
        let credit = BuiltInFilterCredits.credit(for: liveFilter)
        return VStack(alignment: .leading, spacing: 16) {
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
                    InfoMetadataRow(title: "Source Rules", value: submitted.formatted())
                }
                if let author = credit?.author ?? cachedMetadata.author {
                    InfoMetadataRow(title: "Author", value: author)
                }
                if let homepage = credit?.homepage ?? cachedMetadata.homepage {
                    InfoMetadataRow(title: "Homepage", value: homepage.absoluteString, url: homepage)
                }
                if isDownloaded, !liveFilter.version.isEmpty { InfoMetadataRow(title: "Version", value: liveFilter.version) }
                if liveFilter.url.scheme?.lowercased() == "http" || liveFilter.url.scheme?.lowercased() == "https" {
                    VStack(alignment: .leading, spacing: 6) {
                        InfoMetadataRow(title: "Source URL", value: liveFilter.url.absoluteString, url: liveFilter.url)
                        HStack {
                            CopyURLButton(url: liveFilter.url)
                            FilterFallbacksButton { perform(.fallbacks) { showingFallbacks = true } }
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
                title: "Apply on", onlySelectedSites: liveFilter.onlySelectedSites, selectedSites: liveFilter.selectedSites,
                excludedSites: liveFilter.onlySelectedSites ? nil : liveFilter.excludedSites,
                emptySelectionMessage: "No sites selected. This list will not apply.",
                excludedMessage: "This list will not apply on these sites. Other lists still apply.",
                footer: "Sites include their subdomains. Use * to match any top-level domain, for example amazon.*. Apply changes to update filtering.",
                updateMode: { filterManager.setOnlySelectedSites($0, for: liveFilter.id) },
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
    @StateObject private var editorController = CodeMirrorEditorController(text: "", language: .filterRules)
    @State private var wrapsLines = true
    @State private var analysis: FilterRuleAnalysis?
    @State private var isLoading = true
    @State private var shownKinds: Set<FilterRuleKind> = Set(FilterRuleKind.allCases)
    @State private var rebuildTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private static let highlightedKinds: [FilterRuleKind] = [.network, .elementHiding, .advanced, .removeParam, .unsupported, .duplicate]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SourceControlMetrics.spacing) {
                Text(filter.localizedDisplayName)
                    .font(.headline)
                Spacer()
                SourceViewerControls(
                    wrapsLines: $wrapsLines, onSearch: editorController.openSearch, onClose: { dismiss() }, isLoading: isLoading
                ) {
                    if let analysis { filterMenu(analysis) }
                }
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
            let worker = Task.detached(priority: .userInitiated) { () -> FilterRuleAnalysis in
                var seen = Set<String>()
                for text in earlier {
                    seen.formUnion(FilterRuleAnalysis.ruleSet(from: text, isCancelled: { Task.isCancelled }))
                }
                return FilterRuleAnalysis.analyze(
                    content: content,
                    seenInEarlierLists: seen,
                    isCancelled: { Task.isCancelled }
                )
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
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

    /// Each kind's count sits in its menu item; a legend under the editor
    /// cost a third of an iPhone screen (#1037) and its ViewThatFits/grid
    /// layout hung rotation while Find had the keyboard up (#1036).
    private func filterMenu(_ analysis: FilterRuleAnalysis) -> some View {
        Menu {
            ForEach(Self.highlightedKinds, id: \.self) { kind in
                kindToggle(kind, analysis: analysis)
            }
            Divider()
            kindToggle(.comment, analysis: analysis)
        } label: {
            // The chevron marks it as a menu (#948) and the capsule keeps it apart
            // from Wrap Lines' similar bars (#932); tinted while some kinds are hidden.
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
        .padding(.horizontal, 8)
        .frame(height: SourceControlMetrics.size)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
        .accessibilityLabel("View")
        .help("View")
    }

    private func kindToggle(_ kind: FilterRuleKind, analysis: FilterRuleAnalysis) -> some View {
        Toggle(isOn: Binding(
            get: { shownKinds.contains(kind) },
            set: { on in
                if on { shownKinds.insert(kind) } else { shownKinds.remove(kind) }
            }
        )) {
            Label {
                Text(verbatim: "\(Self.title(for: kind)) (\(analysis.count(of: kind).formatted()))")
            } icon: {
                Image(systemName: Self.symbol(for: kind))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Self.color(for: kind))
            }
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
        case .network: return String(localized: "Network Rules")
        case .elementHiding: return String(localized: "Element Hiding")
        case .advanced: return String(localized: "Needs wBlock Scripts")
        case .removeParam: return String(localized: "URL Parameters")
        case .unsupported: return String(localized: "Unsupported")
        case .duplicate: return String(localized: "Duplicates")
        }
    }

    private static func symbol(for kind: FilterRuleKind) -> String {
        switch kind {
        case .comment: return "text.quote"
        case .network: return "network"
        case .elementHiding: return "eye.slash"
        case .advanced: return "curlybraces"
        case .removeParam: return "link.badge.plus"
        case .unsupported: return "xmark.circle"
        case .duplicate: return "doc.on.doc"
        }
    }

    static func color(for kind: FilterRuleKind) -> Color {
        switch kind {
        // Menus bake the icon color, so .secondary came out dark on dark menus.
        case .comment: return .gray
        case .network: return .green
        case .elementHiding: return .orange
        case .advanced: return .blue
        // Pink, since teal read as the same blue as wBlock Scripts.
        case .removeParam: return .pink
        case .unsupported: return .red
        case .duplicate: return .indigo
        }
    }

}
