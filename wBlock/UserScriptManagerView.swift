//
//  UserScriptManagerView.swift
//  wBlock
//
//  Created by Alexander Skula on 6/7/25.
//

import SwiftUI
import wBlockCoreService
import UniformTypeIdentifiers

private extension FilterListCategory {
    static var userScriptCategories: [FilterListCategory] {
        [.scriptBlocking, .scriptFunctionality, .scriptExperimental, .scriptAppearance, .scriptOther]
    }

    var userScriptCategoryName: String {
        if self == .scriptExperimental { return NSLocalizedString("Experimental", comment: "Userscript category") }
        return (isUserScriptOnly ? self : .scriptOther).localizedName
    }

    var userScriptDisplayCategory: UserScriptDisplayCategory? {
        switch self {
        case .scriptBlocking: return .blocking
        case .scriptFunctionality: return .functionality
        case .scriptExperimental: return .experimental
        case .scriptAppearance: return .appearance
        case .scriptOther: return .other
        default: return nil
        }
    }
}

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private struct UserScriptListItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let localizedDisplayName: String
    let localizedDisplayDescription: String
    /// Built once here so rows that scroll in skip the defaults read and formatting.
    let metadataSummary: String
    let url: URL?
    let updateURL: String?
    let isEnabled: Bool
    let version: String
    let lastUpdated: Date?
    let isLocal: Bool
    let isDownloaded: Bool
    let updatesAutomatically: Bool
    let isUserStyle: Bool
    var category: FilterListCategory
    var displayCategory: UserScriptDisplayCategory
    let isBuiltIn: Bool
    let isCustom: Bool
    let isBeta: Bool
    let isDarkReader: Bool
    let isTubeCleaner: Bool
    let isDeArrow: Bool
    let isPlayerCleaner: Bool

    init(
        script: UserScript,
        isDownloaded: Bool,
        isBuiltIn: Bool,
        builtInDisplayRole: BuiltInUserScriptDisplayRole?,
        isBeta: Bool = false,
        isDarkReader: Bool = false,
        isTubeCleaner: Bool = false,
        isDeArrow: Bool = false,
        isPlayerCleaner: Bool = false
    ) {
        id = script.id
        name = script.name
        localizedDisplayName = script.localizedDisplayName
        localizedDisplayDescription = script.localizedDisplayDescription
        metadataSummary = ContentRowMetadata.summary([
            NSLocalizedString(script.isUserStyle ? "Userstyle" : "Userscript", comment: "Content type"),
            ContentRowMetadata.versionLabel(isDownloaded || script.isLocal ? script.version : ""),
            ContentRowMetadata.updatedLabel(
                isDownloaded || script.isLocal ? (UserScriptModifiedStore.date(for: script.url) ?? script.lastUpdated) : nil
            ),
        ])
        url = script.url
        updateURL = script.updateURL
        isEnabled = script.isEnabled
        version = isDownloaded || script.isLocal ? script.version : ""
        lastUpdated = isDownloaded || script.isLocal ? script.lastUpdated : nil
        isLocal = script.isLocal
        self.isDownloaded = isDownloaded
        updatesAutomatically = script.updatesAutomatically
        isUserStyle = script.isUserStyle
        category = script.category
        displayCategory = UserScriptDisplayCategorySupport.category(
            isUserStyle: script.isUserStyle,
            builtInRole: builtInDisplayRole,
            persistedCategory: script.category,
            isBeta: isBeta
        )
        self.isBuiltIn = isBuiltIn
        isCustom = !isBuiltIn
        self.isBeta = isBeta
        self.isDarkReader = isDarkReader
        self.isTubeCleaner = isTubeCleaner
        self.isDeArrow = isDeArrow
        self.isPlayerCleaner = isPlayerCleaner
    }
}

private struct UserScriptDisplaySection: Identifiable {
    let id: UserScriptDisplayCategory
    var title: LocalizedStringKey { LocalizedStringKey(id.rawValue) }
    let scripts: [UserScriptListItem]
}

private struct SelectedUserScript: Identifiable {
    let id: UUID
    let action: UserScriptContextMenuAction
}

private enum BetaUserscriptWarning {
    static let acknowledgedKey = "wBlock.hasAcknowledgedBetaUserscriptWarning"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: GroupIdentifier.shared.value) ?? .standard
    }

    static var hasAcknowledged: Bool {
        defaults.bool(forKey: acknowledgedKey)
    }

    static func acknowledge() {
        defaults.set(true, forKey: acknowledgedKey)
    }
}

struct UserScriptManagerView: View {
    @ObservedObject var userScriptManager: UserScriptManager
    let tabSelection: AppTabSelection
    /// Incremented by ContentView for ⌘⇧N / ⌘L; see `handledAddRequest`.
    let addRequest: Int
    let searchRequest: Int
    let onRefresh: () async -> Void

    @State private var scripts: [UserScriptListItem] = []
    @AppStorage(ListDisplayOrder.scriptsKey) private var scriptDisplayOrder = Data()
    @State private var addingKind: AddUserScriptView.Kind?
    @State private var selectedScript: SelectedUserScript?
    @State private var selectedScriptInfo: SelectedUserScript?
    @State private var selectedScriptSettings: SelectedUserScript?
    @State private var showOnlyEnabled = false
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var downloadingScriptIDs = Set<UUID>()
    @State private var isDropTarget = false
    @State private var isDropProcessing = false
    @State private var dropErrorMessage: String?
    @State private var pendingBetaEnableScript: UserScriptListItem?
    @State private var selectedCategoryInfo: UserScriptDisplayCategory?
    @State private var handledAddRequest = 0
    @State private var handledSearchRequest = 0

    private var totalScriptsCount: Int {
        scripts.filter { !$0.isUserStyle }.count
    }

    private var totalStylesCount: Int {
        scripts.filter(\.isUserStyle).count
    }

    private var enabledScriptsCount: Int {
        scripts.filter(\.isEnabled).count
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedScripts: [UserScriptListItem] {
        let filteredByEnabled = showOnlyEnabled ? orderedScripts.filter(\.isEnabled) : orderedScripts
        let filteredBySearch: [UserScriptListItem]

        if trimmedSearchText.isEmpty {
            filteredBySearch = filteredByEnabled
        } else {
            filteredBySearch = filteredByEnabled.filter { script in
                script.localizedDisplayName.localizedCaseInsensitiveContains(trimmedSearchText)
                    || script.localizedDisplayDescription.localizedCaseInsensitiveContains(trimmedSearchText)
                    || (script.url?.absoluteString.localizedCaseInsensitiveContains(trimmedSearchText)
                        ?? false)
                    || (script.updateURL?.localizedCaseInsensitiveContains(trimmedSearchText) ?? false)
            }
        }

        return filteredBySearch
    }

    private var orderedScripts: [UserScriptListItem] {
        ListDisplayOrder.sorted(scripts.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }, order: scriptDisplayOrder)
    }

    private var displayedScriptSections: [UserScriptDisplaySection] {
        UserScriptDisplayCategory.allCases.compactMap { category in
            let matching = displayedScripts.filter { $0.displayCategory == category }
            return matching.isEmpty ? nil : UserScriptDisplaySection(id: category, scripts: matching)
        }
    }

    private func moveScript(_ id: UUID, to category: UserScriptDisplayCategory) {
        guard let script = userScriptManager.userScript(withId: id),
              let category = FilterListCategory.allCases.first(where: { $0.userScriptDisplayCategory == category }) else { return }
        Task {
            await userScriptManager.setUserScript(script, category: category)
            refreshScripts()
        }
    }

    private func scriptRows(_ section: UserScriptDisplaySection) -> some View {
        ReorderableRows(items: section.scripts, allItems: { orderedScripts },
                        order: $scriptDisplayOrder) { script in
            scriptRowView(script: script)
        }
    }

    var body: some View {
        userScriptContent
        .modifier(scriptsToolbar)
        .sheet(item: $addingKind, onDismiss: {
            refreshScripts()
        }) { kind in
            AddUserScriptView(userScriptManager: userScriptManager, kind: kind, onScriptAdded: {
                refreshScripts()
            })
        }
        .infoPresentation(item: $selectedScriptInfo, onDismiss: refreshScripts, content: scriptInfoContent)
        .infoPresentation(item: $selectedScriptSettings, onDismiss: refreshScripts) { selection in
            UserScriptSettingsView(scriptID: selection.id, userScriptManager: userScriptManager)
                .infoSheetPresentationCompat()
        }
        .sheet(item: $selectedScript, onDismiss: refreshScripts) { selection in
            UserScriptContentView(
                scriptId: selection.id,
                userScriptManager: userScriptManager,
                startsEditing: selection.action == .editContent,
                metadataOnly: selection.action == .editInfo
            )
        }
        .infoPresentation(item: $selectedCategoryInfo, content: scriptCategoryInfoContent)
        .onAppear {
            refreshScripts()
            showOnlyEnabled = ProtobufDataManager.shared.getUserScriptShowEnabledOnly()
        }
        .onReceive(userScriptManager.$userScripts) { updatedScripts in
            // @Published emits in willSet, so use the emitted array instead of
            // reading the manager's still-stale value during this callback.
            refreshScripts(updatedScripts)
        }
        .onReceive(tabSelection.$value.removeDuplicates().dropFirst()) { _ in
            searchText = ""
            showSearch = false
        }
        // task(id:) runs on appear too, so a request sent while this tab was
        // not yet built is still honored once it is.
        .task(id: addRequest) {
            guard addRequest > 0, addRequest != handledAddRequest else { return }
            handledAddRequest = addRequest
            addingKind = .script
        }
        .task(id: searchRequest) {
            guard searchRequest > 0, searchRequest != handledSearchRequest else { return }
            handledSearchRequest = searchRequest
            showSearch = true
        }
        .alert("Import Failed", isPresented: Binding(
            get: { dropErrorMessage != nil },
            set: { newValue in if !newValue { dropErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { dropErrorMessage = nil }
        } message: {
            Text(dropErrorMessage ?? "")
        }
        .alert("Enable Beta Userscript?", isPresented: Binding(
            get: { pendingBetaEnableScript != nil },
            set: { newValue in if !newValue { pendingBetaEnableScript = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingBetaEnableScript = nil }
            Button("Enable") {
                guard let script = pendingBetaEnableScript else { return }
                pendingBetaEnableScript = nil
                BetaUserscriptWarning.acknowledge()
                applyEnabledState(for: script, newValue: true)
            }
        } message: {
            Text("Beta userscripts are still being tested and may break pages or behave unexpectedly. You can turn them off at any time.")
        }
    }

    @ViewBuilder
    private var userScriptContent: some View {
        let sections = displayedScriptSections
        #if os(iOS)
        List {
            Section {
                statsCardsView
                    .unifiedTabCardSectionRow()
            }

            if scripts.isEmpty {
                Section {
                    emptyStateView
                        .padding(.vertical, 40)
                }
            } else if sections.isEmpty {
                Section {
                    noSearchResultsView
                        .padding(.vertical, 40)
                }
            } else {
                ForEach(sections) { scriptSection in
                    ContentListSection { displaySectionHeader(scriptSection) } content: {
                        scriptRows(scriptSection)
                    }
                }
            }
        }
        .unifiedTabListStyle()
        .refreshable {
            await onRefresh()
        }
        .searchableCompat(
            text: $searchText,
            isPresented: $showSearch,
            prompt: "Search scripts"
        )
        #else
        MacReorderableList(
            sections: scripts.isEmpty || sections.isEmpty ? [] : macScriptSections,
            header: AnyView(statsCardsView.padding(.vertical, 16)),
            emptyContent: scripts.isEmpty ? AnyView(emptyStateView.padding(.vertical, 40))
                : (sections.isEmpty ? AnyView(noSearchResultsView.padding(.vertical, 40)) : nil),
            onMove: commitScriptMove
        )
        .scrollingUnderToolbar()
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget, perform: handleDrop(providers:))
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .padding(8)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.accentColor.opacity(0.05))
                                .padding(8)
                        }
                }

                if isDropProcessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Importing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
                }
            }
        }
        #endif
    }

    #if os(macOS)
    private var macScriptSections: [MacListSection] {
        UserScriptDisplayCategory.allCases.map { category in
            let section = UserScriptDisplaySection(id: category, scripts: displayedScripts.filter { $0.displayCategory == category })
            return MacListSection(id: category.id, header: AnyView(displaySectionHeader(section)),
                                  rows: section.scripts.map { script in MacListRow(script.id) { scriptRowView(script: script) } },
                                  revealsOnlyWhileDragging: true)
        }
    }

    private func commitScriptMove(_ move: MacListMove) -> Bool {
        guard let category = UserScriptDisplayCategory(rawValue: move.sectionID),
              let persisted = FilterListCategory.allCases.first(where: { $0.userScriptDisplayCategory == category }),
              let index = scripts.firstIndex(where: { $0.id == move.itemID }),
              userScriptManager.userScript(withId: move.itemID) != nil else { return false }
        let all = orderedScripts
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let moved = move.orderedIDs.compactMap { byID[$0] }
        guard moved.count == move.orderedIDs.count else { return false }
        scriptDisplayOrder = ListDisplayOrder.saving(moved, in: all)
        if byID[move.itemID]?.displayCategory != category {
            scripts[index].category = persisted
            scripts[index].displayCategory = category
            moveScript(move.itemID, to: category)
        }
        return true
    }

    #endif

    private var scriptsToolbar: some ViewModifier {
        ListActionsToolbar(
            searchText: $searchText,
            focusRequest: $showSearch,
            showEnabledOnly: Binding(
                get: { showOnlyEnabled },
                set: {
                    showOnlyEnabled = $0
                    ProtobufDataManager.shared.setUserScriptShowEnabledOnly($0)
                }
            ),
            searchPrompt: "Search scripts"
        ) {
            addMenu
        } apply: {
            EmptyView()
        }
    }

    /// Add asks which kind first so the sheet can name it and start the
    /// editor from the right metadata block (#933).
    private var addMenu: some View {
        Menu {
            Button { addingKind = .script } label: {
                Label("Userscript", systemImage: "curlybraces")
            }
            Button { addingKind = .style } label: {
                Label("Userstyle", systemImage: "paintbrush")
            }
        } label: {
            Label("Add Userscript or Userstyle", systemImage: "plus")
        }
    }

    private func refreshScripts() {
        refreshScripts(userScriptManager.userScripts)
    }

    private func refreshScripts(_ updatedScripts: [UserScript]) {
        scripts = updatedScripts.map { script in
            UserScriptListItem(
                script: script,
                isDownloaded: userScriptManager.hasDownloadedContent(for: script),
                isBuiltIn: userScriptManager.isDefaultUserScript(script),
                builtInDisplayRole: userScriptManager.builtInDisplayRole(for: script),
                isBeta: userScriptManager.isBeta(for: script),
                isDarkReader: userScriptManager.isDarkReader(script),
                isTubeCleaner: userScriptManager.isTubeCleaner(script),
                isDeArrow: userScriptManager.isDeArrow(script),
                isPlayerCleaner: userScriptManager.isPlayerCleaner(script)
            )
        }
    }

    #if os(macOS)
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let error {
                Task {
                    await ConcurrentLogManager.shared.error(.userScript, LocalizedStrings.text("Failed to load dropped item"), metadata: ["error": LogErrorDescriber.describe(error)])
                }
                return
            }

            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let droppedURL = item as? URL {
                url = droppedURL
            }

            guard let resolvedURL = url else {
                Task {
                    await ConcurrentLogManager.shared.error(.userScript, LocalizedStrings.text("Could not resolve URL from dropped item."))
                }
                return
            }

            Task {
                await MainActor.run { isDropProcessing = true }

                let error = await userScriptManager.addUserScript(fromLocalFile: resolvedURL)
                if let error {
                    await ConcurrentLogManager.shared.error(.userScript, LocalizedStrings.text("Failed to import dropped userscript"), metadata: ["error": LogErrorDescriber.describe(error)])
                    await MainActor.run {
                        dropErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                } else {
                    await MainActor.run {
                        refreshScripts()
                    }
                }

                await MainActor.run { isDropProcessing = false }
            }
        }

        return true
    }
    #endif

    private var statsCardsView: some View {
        // Three full cards overflow an iPhone row (#626). With a style installed
        // the cards drop to the compact layout, which keeps one row of three.
        let compact: Bool = {
            #if os(iOS)
            totalStylesCount > 0
            #else
            false
            #endif
        }()
        return StatsCardsView(compact: compact) {
            StatCard(
                title: "Scripts",
                value: "\(totalScriptsCount)",
                icon: "doc.text",
                compact: compact
            )

            if totalStylesCount > 0 {
                StatCard(
                    title: "Styles",
                    value: "\(totalStylesCount)",
                    icon: "paintbrush",
                    compact: compact
                )
            }

            StatCard(
                title: "Enabled",
                value: "\(enabledScriptsCount)",
                icon: "checkmark.circle",
                compact: compact
            )
        }
    }

    private func displaySectionHeader(_ section: UserScriptDisplaySection) -> some View {
        ListCategoryHeader(title: section.title, info: { selectedCategoryInfo = section.id }, anchorID: section.id.id)
    }

    private func scriptInfoContent(_ selection: SelectedUserScript) -> some View {
        UserScriptInfoView(
            scriptId: selection.id, userScriptManager: userScriptManager,
            onChangeDisplayCategory: { moveScript(selection.id, to: $0) },
            onDownload: {
                if let item = scripts.first(where: { $0.id == selection.id }) { requestEnable(item) }
            },
            onAction: macOSWindowAction { action in
                let routed = SelectedUserScript(id: selection.id, action: action)
                if action == .settings { selectedScriptSettings = routed } else { selectedScript = routed }
            }
        ).tallInfoSheetPresentationCompat()
    }

    private func scriptCategoryInfoContent(_ category: UserScriptDisplayCategory) -> some View {
        UserScriptCategoryInfoView(
            category: category, defaultScriptNames: defaultScriptNames(for: category),
            onReset: { resetCategory(category) }
        ).infoSheetPresentationCompat()
    }

    private func defaultScriptNames(for category: UserScriptDisplayCategory) -> [String] {
        UserScriptCategorySupport.defaultScriptNames(
            for: category,
            scripts: userScriptManager.userScripts.map { script in
                (
                    name: script.name,
                    displayCategory: UserScriptDisplayCategorySupport.category(
                        isUserStyle: script.isUserStyle,
                        builtInRole: userScriptManager.builtInDisplayRole(for: script),
                        persistedCategory: script.category,
                        isBeta: userScriptManager.isBeta(for: script)
                    ),
                    isEnabledByDefault: userScriptManager.isEnabledByDefault(script)
                )
            }
        )
    }

    private func resetCategory(_ category: UserScriptDisplayCategory) {
        var enabledIDs = Set(
            userScriptManager.userScripts.filter(\.isEnabled).map(\.id)
        )
        for script in userScriptManager.userScripts {
            let displayCategory = UserScriptDisplayCategorySupport.category(
                isUserStyle: script.isUserStyle,
                builtInRole: userScriptManager.builtInDisplayRole(for: script),
                persistedCategory: script.category,
                isBeta: userScriptManager.isBeta(for: script)
            )
            guard let shouldEnable = UserScriptCategorySupport.resetEnabled(
                isBuiltIn: userScriptManager.isDefaultUserScript(script),
                displayCategory: displayCategory,
                category: category,
                isEnabledByDefault: userScriptManager.isEnabledByDefault(script)
            ) else { continue }
            if shouldEnable {
                enabledIDs.insert(script.id)
            } else {
                enabledIDs.remove(script.id)
            }
        }
        Task {
            await userScriptManager.setEnabledScripts(withIDs: enabledIDs)
            await MainActor.run { refreshScripts() }
        }
    }

    /// Fetches a remote script's content without changing its enabled state (#665).
    /// Get and the switch both enable through here, so Get turns the script
    /// on as it does for filter lists, and a beta warns before downloading (#941).
    private func requestEnable(_ script: UserScriptListItem) {
        guard !downloadingScriptIDs.contains(script.id) else { return }
        if script.isBeta, !BetaUserscriptWarning.hasAcknowledged {
            pendingBetaEnableScript = script
            return
        }
        applyEnabledState(for: script, newValue: true)
    }

    private func applyEnabledState(for script: UserScriptListItem, newValue: Bool) {
        guard let latestState = userScriptManager.userScriptToggleState(for: script.id),
              latestState.desired != newValue
        else { return }
        let managedScript = userScriptManager.userScript(withId: script.id)
        let shouldDownloadBeforeEnabling =
            // Disabled scripts drop their content from memory, so check the file.
            newValue && !(managedScript.map(userScriptManager.hasDownloadedContent) ?? script.isDownloaded)
                && !(managedScript?.isLocal ?? script.isLocal)
                && (managedScript?.url ?? script.url) != nil
        if shouldDownloadBeforeEnabling {
            downloadingScriptIDs.insert(script.id)
        }

        Task {
            guard let managedScript = userScriptManager.userScript(withId: script.id) else {
                await MainActor.run { _ = downloadingScriptIDs.remove(script.id) }
                return
            }
            await ConcurrentLogManager.shared.debug(
                .userScript,
                LocalizedStrings.text("Setting userscript enabled state"),
                metadata: ["script": script.name, "enabled": "\(newValue)"]
            )
            await userScriptManager.setUserScript(managedScript, isEnabled: newValue)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    downloadingScriptIDs.remove(script.id)
                    refreshScripts()
                }
            }
        }
    }

    private func scriptRowView(script: UserScriptListItem) -> some View {
        let managedScript = userScriptManager.userScript(withId: script.id)
        let toggleState = userScriptManager.userScriptToggleState(for: script.id)
        let displayedEnabled = toggleState?.desired ?? managedScript?.isEnabled ?? script.isEnabled
        let isToggleInFlight = toggleState?.isInFlight ?? false

        return HStack(alignment: .center, spacing: 10) {
            // Keep the iOS info gesture on the text column so it cannot consume switch taps.
            HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(script.localizedDisplayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if script.isLocal {
                        Badge(text: "Local Import", color: .blue)
                    } else if script.isCustom {
                        Badge(text: "Custom", color: .blue)
                    }
                    if script.isBeta {
                        Badge(text: "Beta", color: .orange)
                    }
                    #if os(iOS)
                    RowDisclosureChevron()
                    #endif
                }

                if !script.localizedDisplayDescription.isEmpty {
                    Text(script.localizedDisplayDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // One metadata line: kind, version, and update time. The Info
                // sheet carries the full detail.
                Text(script.metadataSummary)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if displayedEnabled && !script.isDownloaded && script.isLocal {
                    Text("Not Downloaded")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .cornerRadius(4)
                }

                if script.isDarkReader {
                    DarkReaderAppearancePicker(
                        followsSystemAppearance: Binding(
                            get: { userScriptManager.darkReaderFollowsSystemAppearance },
                            set: { userScriptManager.setDarkReaderFollowsSystemAppearance($0) }
                        )
                    )
                }

                if script.isTubeCleaner {
                    // Side by side when the column is wide enough, stacked otherwise.
                    if #available(iOS 16.0, macOS 13.0, *) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) { tubeCleanerControls(script) }
                            VStack(alignment: .leading, spacing: 4) { tubeCleanerControls(script) }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) { tubeCleanerControls(script) }
                    }
                }
                if script.isPlayerCleaner {
                    PlayerCleanerFeaturesPicker(
                        features: Binding(
                            get: { userScriptManager.playerCleanerFeatures },
                            set: { userScriptManager.setPlayerCleanerFeatures($0) }
                        )
                    )
                }
                if script.isDeArrow {
                    DeArrowSettingsPicker(
                        settings: Binding(
                            get: { userScriptManager.tubeCleanerDeArrow },
                            set: { userScriptManager.setTubeCleanerDeArrow($0) }
                        )
                    )
                }
            }

            Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                selectedScriptInfo = SelectedUserScript(id: script.id, action: .info)
            }
            .contentShape(.interaction, Rectangle())
            #if os(iOS)
            .onTapGesture {
                // Defer to avoid race with context menu dismissal on iOS.
                DispatchQueue.main.async {
                    selectedScriptInfo = SelectedUserScript(id: script.id, action: .info)
                }
            }
            #endif
            #if os(macOS)
            Button { selectedScriptInfo = SelectedUserScript(id: script.id, action: .info) } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain).noFocusRingCompat()
            .foregroundStyle(.secondary).accessibilityLabel("Info")
            .infoPopoverAnchor(script.id)
            #endif

            if !script.isLocal && (downloadingScriptIDs.contains(script.id) || !script.isDownloaded) {
                // A switch is meaningless until the script exists, so the
                // row offers Get in its place.
                ContentDownloadControl(
                    isDownloaded: script.isDownloaded,
                    isDownloading: downloadingScriptIDs.contains(script.id),
                    name: script.name, action: { requestEnable(script) }
                )
            } else {
                Toggle("", isOn: Binding(
                    get: { displayedEnabled },
                    set: { newValue in
                        if newValue { requestEnable(script) } else { applyEnabledState(for: script, newValue: false) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
                .disabled(isToggleInFlight || (script.isLocal && !script.isDownloaded))
            }
        }
        .id(script.id)
        #if os(macOS)
        .contextMenu { scriptMenuItems(script) }
        .padding(16)
        #else
        // iOS keeps one control flush right. The chevron by the title says
        // the row opens; the Info sheet lists every action, and long press
        // is a shortcut to the same actions.
        .contextMenu { scriptMenuItems(script) }

        #endif
    }

    @ViewBuilder
    private func tubeCleanerControls(_ script: UserScriptListItem) -> some View {
        SponsorBlockTransferButton(scriptID: script.id)
        TubeCleanerFeaturesPicker(
            features: Binding(
                get: { userScriptManager.tubeCleanerFeatures },
                set: { userScriptManager.setTubeCleanerFeatures($0) }
            )
        )
    }

    private func removeScript(_ managedScript: UserScript, name: String) {
        Task {
            await ConcurrentLogManager.shared.info(.userScript, LocalizedStrings.text("Removing userscript"), metadata: ["script": name])
            await userScriptManager.removeUserScript(managedScript)
            refreshScripts()
        }
    }

    @ViewBuilder
    private func scriptMenuItems(_ script: UserScriptListItem) -> some View {
        let actions = ContextMenuActionAvailability.userScriptActions(
            isBuiltIn: script.isBuiltIn,
            isLocal: script.isLocal,
            isDownloaded: script.isDownloaded
        )
        if actions.contains(.info) {
            Button { selectedScriptInfo = SelectedUserScript(id: script.id, action: .info) } label: {
                Label("Info", systemImage: "info.circle")
            }
        }
        if actions.contains(.settings) {
            Button { selectedScriptSettings = SelectedUserScript(id: script.id, action: .settings) } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        if actions.contains(.viewContent) {
            Button { selectedScript = SelectedUserScript(id: script.id, action: .viewContent) } label: {
                Label("View Content", systemImage: "doc.text")
            }
        }
        if actions.contains(.editContent) {
            Button { selectedScript = SelectedUserScript(id: script.id, action: .editContent) } label: {
                Label("Edit Content", systemImage: "pencil")
            }
        }
        if actions.contains(.download) {
            Button { requestEnable(script) } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .disabled(downloadingScriptIDs.contains(script.id))
        }
        if actions.contains(.moveTo) {
            Picker(selection: Binding(
                get: { script.displayCategory },
                set: { category in moveScript(script.id, to: category) }
            )) {
                ForEach(UserScriptDisplayCategory.allCases) { category in
                    Text(LocalizedStringKey(category.rawValue)).tag(category)
                }
            } label: {
                Label("Move to", systemImage: "folder")
            }
        }
        if actions.contains(.deleteScript),
           let managedScript = userScriptManager.userScript(withId: script.id) {
            Button(role: .destructive) {
                removeScript(managedScript, name: script.name)
            } label: {
                Label(script.isUserStyle ? "Delete Style" : "Delete Script", systemImage: "trash")
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .scaledSystemFont(size: 48, relativeTo: .largeTitle)
                .foregroundStyle(.secondary.opacity(0.6))
            Text("No Userscripts")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Add userscripts and userstyles to customize your browsing experience")
                .font(.body)
                .foregroundStyle(.secondary)
            addMenu
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .scaledSystemFont(size: 36, relativeTo: .largeTitle)
                .foregroundStyle(.secondary.opacity(0.7))
            Text("No matching userscripts")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UserScriptInfoSidebar Subviews

private struct ScriptStatusBadgesView: View {
    let script: UserScript
    let isDownloaded: Bool
    let isBuiltIn: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(InfoBadgeSupport.userScriptBadges(
                    script,
                    isDownloaded: isDownloaded,
                    isBuiltIn: isBuiltIn
                ).enumerated()), id: \.offset) { _, badge in
                    InfoBadgeView(kind: badge)
                }
            }
        }
    }
}

private struct ScriptURLView: View {
    let script: UserScript

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = script.url {
                InfoMetadataRow(title: "Source URL", value: url.absoluteString, url: url)
                CopyURLButton(url: url)
            }
        }
    }
}

private struct ScriptMatchPatternRowView: View {
    let index: Int
    let total: Int
    let pattern: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Size the number column from the largest index so "1000." never
            // wraps onto two lines (#614); the monospaced digits keep it aligned.
            Text(
                LocalizedStrings.format(
                    "%d.",
                    comment: "Userscript URL pattern row index",
                    index + 1
                )
            )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: CGFloat(6 * (String(total).count + 1)), alignment: .trailing)

            Text(pattern)
                .font(.caption)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

private extension UserScript {
    /// Userstyles persist serialized @-moz-document conditions in `matches`;
    /// render them in a human-readable form instead of the storage format.
    func displayMatchPattern(_ pattern: String) -> String {
        guard isUserStyle else { return pattern }
        if pattern == "global" {
            return LocalizedStrings.text("All websites", comment: "Userstyle condition that applies everywhere")
        }
        for prefix in ["domain:", "url-prefix:", "url:", "regexp:"] where pattern.hasPrefix(prefix) {
            let value = String(pattern.dropFirst(prefix.count))
            return prefix == "url-prefix:" ? value + "…" : value
        }
        return pattern
    }

    var matchPatternsTitle: String {
        isUserStyle
            ? LocalizedStrings.format("Applies To (%d)", comment: "Userstyle condition section title", matches.count)
            : LocalizedStrings.format("URL Patterns (%d)", comment: "Userscript URL pattern section title", matches.count)
    }
}

/// Opens the pattern list in its own sheet, so long lists no longer stretch the info panel.
private struct ScriptMatchPatternsButton: View {
    let script: UserScript
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet").frame(width: 22)
                Text(script.matchPatternsTitle)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
    }
}

private struct ScriptMatchPatternsSheet: View {
    let script: UserScript
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            InfoSheetHeader {
                Text(script.matchPatternsTitle)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } onDismiss: { dismiss() }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(script.matches.indices, id: \.self) { index in
                        ScriptMatchPatternRowView(
                            index: index,
                            total: script.matches.count,
                            pattern: script.displayMatchPattern(script.matches[index])
                        )
                    }
                }
                .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                .padding(.bottom, SheetDesign.contentHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 400)
        #endif
    }
}

struct UserScriptSettingsView: View {
    let scriptID: UUID
    @ObservedObject var userScriptManager: UserScriptManager

    var body: some View {
        if let script = userScriptManager.userScript(withId: scriptID) {
            ContentSettingsView(name: script.localizedDisplayName) {
                if !script.isLocal && script.resolvedDownloadURL != nil {
                    AutomaticUpdatesToggle(
                        isOn: script.updatesAutomatically,
                        description: "Turn this off to keep the current version when wBlock updates scripts in bulk or on a schedule."
                    ) { enabled in
                        Task { await userScriptManager.setUserScript(script, updatesAutomatically: enabled) }
                    }
                }
                UserScriptWebsiteExceptionsView(scriptID: scriptID, userScriptManager: userScriptManager)
            }
        } else {
            Text("Unable to load script")
        }
    }
}


struct UserScriptInfoSidebar: View {
    let script: UserScript
    let contentLength: Int
    let isDownloaded: Bool
    let formatFileSize: (Int) -> String
    let isBuiltIn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let sourceMetadata = ContentInfoMetadata.userscript(script.content)
            let metadata = ContentInfoMetadata(
                author: script.author ?? sourceMetadata.author,
                homepage: script.homepage.flatMap(URL.init(string:)) ?? sourceMetadata.homepage
            )
            VStack(alignment: .leading, spacing: 8) {
                if !script.localizedDisplayDescription.isEmpty {
                    Text(script.localizedDisplayDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScriptStatusBadgesView(script: script, isDownloaded: isDownloaded, isBuiltIn: isBuiltIn)
            }
            InfoMetadataList {
                InfoMetadataRow(title: "Type", value: NSLocalizedString(
                    script.isUserStyle ? "Userstyle" : "Userscript",
                    comment: "Content type"
                ), valueStyle: .typeBadge)
                InfoMetadataRow(title: "Author", value: metadata.author ?? String(localized: "Not provided"))
                InfoMetadataRow(
                    title: "Homepage",
                    value: metadata.homepage?.absoluteString ?? String(localized: "Not provided"),
                    url: metadata.homepage
                )
                if isDownloaded, !script.version.isEmpty { InfoMetadataRow(title: "Version", value: script.version) }
                if script.url != nil { ScriptURLView(script: script) }
                if contentLength > 0 { InfoMetadataRow(title: "Size", value: formatFileSize(contentLength)) }
            }
        }
    }
}

struct UserScriptInfoView: View {
    let scriptId: UUID
    var userScriptManager: UserScriptManager
    var onChangeDisplayCategory: ((UserScriptDisplayCategory) -> Void)? = nil
    var onDownload: (() -> Void)? = nil
    /// Presents an action's sheet from the window instead of this view. A
    /// macOS popover would otherwise anchor the sheet to itself (#923).
    var onAction: ((UserScriptContextMenuAction) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var script: UserScript?
    @State private var showingPatterns = false
    @State private var isLoading = true
    @State private var showingMetadataEditor = false
    @State private var showingSettings = false
    @State private var showingSource = false
    @State private var confirmingDelete = false

    // Persisted metadata is already available; disk hydration only enriches it.
    private var liveScript: UserScript? {
        script ?? userScriptManager.userScript(withId: scriptId)
    }

    var body: some View {
        Group {
            if let script = liveScript {
                InfoSheetContainer {
                    InfoSheetHeader {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(script.localizedDisplayName)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if userScriptManager.isBeta(for: script) {
                                Badge(text: "Beta", color: .orange)
                            }
                        }
                    } onDismiss: { dismiss() }
                } content: {
                    UserScriptInfoSidebar(
                        script: script,
                        contentLength: script.content.utf8.count,
                        isDownloaded: userScriptManager.hasDownloadedContent(for: script),
                        formatFileSize: formatFileSize,
                        isBuiltIn: userScriptManager.isDefaultUserScript(script)
                    )
                    actionList(for: script)
                }
                #if os(macOS)
                .frame(width: 460)
                #endif
            } else if isLoading {
                VStack(spacing: 0) {
                    InfoSheetHeader { EmptyView() } onDismiss: { dismiss() }
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                #if os(macOS)
                .frame(width: 460)
                #endif
            } else {
                VStack(spacing: 0) {
                    InfoSheetHeader { EmptyView() } onDismiss: { dismiss() }
                    Text("Unable to load script")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                #if os(macOS)
                .frame(width: 460)
                #endif
            }
        }
        .sheet(isPresented: $showingMetadataEditor, onDismiss: {
            Task { script = await userScriptManager.userScriptEditorSnapshot(withId: scriptId) }
        }) {
            UserScriptContentView(scriptId: scriptId, userScriptManager: userScriptManager, metadataOnly: true)
        }
        .sheet(isPresented: $showingPatterns) {
            if let script = liveScript { ScriptMatchPatternsSheet(script: script) }
        }
        .sheet(isPresented: $showingSettings) {
            UserScriptSettingsView(scriptID: scriptId, userScriptManager: userScriptManager)
                .infoSheetPresentationCompat()
        }
        .sheet(isPresented: $showingSource, onDismiss: {
            Task { script = await userScriptManager.userScriptEditorSnapshot(withId: scriptId) }
        }) {
            UserScriptContentView(
                scriptId: scriptId, userScriptManager: userScriptManager,
                startsEditing: liveScript.map { !userScriptManager.isDefaultUserScript($0) && $0.isLocal } ?? false
            )
        }
        .task(id: scriptId) {
            isLoading = true
            let previous = script
            let snapshot = await userScriptManager.userScriptEditorSnapshot(withId: scriptId)
            guard !Task.isCancelled, script == previous else { return }
            script = snapshot
            isLoading = false
        }
    }

    private func perform(_ action: UserScriptContextMenuAction, locally: () -> Void) {
        guard let onAction else { return locally() }
        dismiss()
        onAction(action)
    }

    @ViewBuilder
    private func actionList(for script: UserScript) -> some View {
        let isBuiltIn = userScriptManager.isDefaultUserScript(script)
        let actions = ContextMenuActionAvailability.userScriptActions(
            isBuiltIn: isBuiltIn, isLocal: script.isLocal,
            isDownloaded: userScriptManager.hasDownloadedContent(for: script)
        )
        InfoActionList {
            if !script.matches.isEmpty {
                ScriptMatchPatternsButton(script: script) { showingPatterns = true }
            }
            if actions.contains(.settings) {
                InfoActionRow("Settings", systemImage: "gearshape") { perform(.settings) { showingSettings = true } }
            }
            if actions.contains(.viewContent) {
                InfoActionRow("View Content", systemImage: "doc.text") { perform(.viewContent) { showingSource = true } }
            }
            if actions.contains(.editContent) {
                InfoActionRow("Edit Content", systemImage: "pencil") { perform(.editContent) { showingSource = true } }
            }
            if actions.contains(.editInfo) {
                InfoActionRow("Edit Info", systemImage: "square.and.pencil") { perform(.editInfo) { showingMetadataEditor = true } }
            }
            if actions.contains(.download), let onDownload {
                InfoActionRow("Download", systemImage: "arrow.down.circle") {
                    onDownload()
                    dismiss()
                }
            }
            if actions.contains(.moveTo) {
                InfoCategoryRow(
                    selection: Binding(
                        get: {
                            UserScriptDisplayCategorySupport.category(
                                isUserStyle: script.isUserStyle,
                                builtInRole: userScriptManager.builtInDisplayRole(for: script),
                                persistedCategory: script.category,
                                isBeta: userScriptManager.isBeta(for: script)
                            )
                        },
                        set: setDisplayCategory
                    ),
                    categories: UserScriptDisplayCategory.allCases,
                    name: { NSLocalizedString($0.rawValue, comment: "Userscript category") }
                )
            }
            if actions.contains(.deleteScript) {
                InfoActionRow(
                    script.isUserStyle ? "Delete Style" : "Delete Script",
                    systemImage: "trash", role: .destructive
                ) { confirmingDelete = true }
                // Anchored to the row so the iPad popover arrow points at it.
                .confirmationDialog(
                    script.isUserStyle ? "Delete Style" : "Delete Script",
                    isPresented: $confirmingDelete, titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        Task {
                            await ConcurrentLogManager.shared.info(.userScript, LocalizedStrings.text("Removing userscript"), metadata: ["script": script.name])
                            await userScriptManager.removeUserScript(script)
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    private func setDisplayCategory(_ category: UserScriptDisplayCategory) {
        guard var currentScript = liveScript,
              let mappedCategory = FilterListCategory.allCases.first(where: { $0.userScriptDisplayCategory == category })
        else { return }
        currentScript.category = mappedCategory
        script = currentScript
        if let onChangeDisplayCategory {
            onChangeDisplayCategory(category)
        } else {
            Task { await userScriptManager.setUserScript(currentScript, category: mappedCategory) }
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Edit Content opens the shared source editor, View Content the read-only
/// viewer, and Edit Info only the metadata fields (#921).
struct UserScriptContentView: View {
    let scriptId: UUID
    var userScriptManager: UserScriptManager
    var startsEditing: Bool = false
    var metadataOnly: Bool = false
    @State private var script: UserScript?
    @State private var loadedContent = ""
    @State private var isLoadingContent = true

    var body: some View {
        Group {
            if let script {
                if metadataOnly {
                    UserScriptMetadataSheet(script: script) { name, description, author, homepage, category in
                        guard await userScriptManager.setUserScriptMetadataOverrides(
                            for: script.id, name: name, description: description,
                            author: author, homepage: homepage
                        ) else {
                            return String(localized: "Couldn't save the edited source.")
                        }
                        await userScriptManager.setUserScript(script, category: category)
                        return nil
                    }
                } else {
                    UserScriptSourceSheet(
                        script: script, content: loadedContent,
                        canEdit: startsEditing && script.isLocal && !userScriptManager.isDefaultUserScript(script)
                    ) { newContent in
                        guard newContent != loadedContent else { return nil }
                        return await userScriptManager.saveEditedContent(for: script.id, newContent: newContent)
                    }
                }
            } else if isLoadingContent {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(macOS)
                    .frame(width: 1000, height: 700)
                    #endif
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .scaledSystemFont(size: 40, relativeTo: .largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Unable to load script")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: scriptId) {
            isLoadingContent = true
            guard let loadedScript = await userScriptManager.userScriptEditorSnapshot(withId: scriptId) else {
                script = nil
                loadedContent = ""
                isLoadingContent = false
                return
            }
            var metadata = loadedScript
            loadedContent = loadedScript.content
            metadata.content = ""
            script = metadata
            isLoadingContent = false
        }
    }
}

/// Script source: the shared editor for local custom scripts, the read-only
/// viewer for everything else.
private struct UserScriptSourceSheet: View {
    let script: UserScript
    let canEdit: Bool
    let onSave: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var editorController: CodeMirrorEditorController
    @State private var wrapsLines = false

    init(script: UserScript, content: String, canEdit: Bool, onSave: @escaping (String) async -> String?) {
        self.script = script
        self.canEdit = canEdit
        self.onSave = onSave
        _editorController = StateObject(
            wrappedValue: CodeMirrorEditorController(text: content, isUserStyle: script.isUserStyle))
    }

    var body: some View {
        if canEdit {
            SourceEditorSheet(title: script.localizedDisplayName, editorController: editorController, onDone: onSave)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(script.localizedDisplayName).font(.headline).lineLimit(1)
                    Spacer()
                    SourceViewerControls(wrapsLines: $wrapsLines, onSearch: editorController.openSearch)
                    SheetDoneButton { dismiss() }
                }
                .padding(16)
                Divider()
                CodeMirrorTextEditor(controller: editorController, isEditable: false, isLineWrappingEnabled: wrapsLines)
            }
            #if os(macOS)
            .frame(width: 1000, height: 700)
            #else
            .sourceSheetPresentationCompat()
            #endif
        }
    }
}

/// Edit Info for custom scripts: the metadata fields filters use, plus author
/// and homepage.
private struct UserScriptMetadataSheet: View {
    let script: UserScript
    let onSave: (String, String, String?, String?, FilterListCategory) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var editedName: String
    @State private var editedDescription: String
    @State private var editedAuthor: String
    @State private var editedHomepage: String
    @State private var selectedCategory: FilterListCategory
    @State private var isSaving = false
    @State private var validationMessage: String?

    init(script: UserScript, onSave: @escaping (String, String, String?, String?, FilterListCategory) async -> String?) {
        self.script = script
        self.onSave = onSave
        _editedName = State(initialValue: script.name)
        _editedDescription = State(initialValue: script.description)
        _editedAuthor = State(initialValue: script.author ?? "")
        _editedHomepage = State(initialValue: script.homepage ?? "")
        _selectedCategory = State(initialValue: script.category.isUserScriptOnly ? script.category : .scriptOther)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(script.localizedDisplayName).font(.headline).lineLimit(1)
                Spacer()
                Button("Save") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || !hasChanges || editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                SheetDoneButton { dismiss() }
                    .disabled(isSaving)
            }
            .padding(16)
            Divider()
            Form {
                Section {
                    AddContentMetadataFields(name: $editedName, description: $editedDescription,
                        category: $selectedCategory, categories: FilterListCategory.userScriptCategories)
                    TextField("Author", text: $editedAuthor)
                    TextField("Homepage", text: $editedHomepage)
                } footer: {
                    if let validationMessage { Text(validationMessage).foregroundStyle(.red) }
                }
            }
            .groupedFormStyleCompat()
            .disabled(isSaving)
        }
        #if os(macOS)
        .frame(width: 460, height: 360)
        #endif
        .interactiveDismissDisabled(isSaving)
    }

    private var hasChanges: Bool {
        editedName != script.name || editedDescription != script.description
            || editedAuthor != (script.author ?? "") || editedHomepage != (script.homepage ?? "")
            || selectedCategory != (script.category.isUserScriptOnly ? script.category : .scriptOther)
    }

    @MainActor private func save() async {
        isSaving = true
        let error = await onSave(editedName.trimmingCharacters(in: .whitespacesAndNewlines),
                                 editedDescription, editedAuthor, editedHomepage, selectedCategory)
        isSaving = false
        if let error { validationMessage = error } else { dismiss() }
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(LocalizedStringKey(text)).font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15)).foregroundStyle(color).cornerRadius(4)
    }
}

private struct DarkReaderAppearancePicker: View {
    @Binding var followsSystemAppearance: Bool

    var body: some View {
        Menu {
            Button {
                followsSystemAppearance = true
            } label: {
                appearanceMenuItem(title: "Follow System", selected: followsSystemAppearance)
            }
            Button {
                followsSystemAppearance = false
            } label: {
                appearanceMenuItem(title: "Always Dark", selected: !followsSystemAppearance)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: followsSystemAppearance ? "circle.lefthalf.filled" : "moon.fill")
                    .imageScale(.small)
                Text(followsSystemAppearance ? "Follow System" : "Always Dark")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .accessibilityLabel("Appearance")
        .accessibilityValue(followsSystemAppearance ? "Follow System" : "Always Dark")
        .padding(.top, 2)
    }

    @ViewBuilder
    private func appearanceMenuItem(title: LocalizedStringKey, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

/// Per-feature switches for Tube Cleaner (#671). Ad handling and native
/// controls are the script's purpose, so they are not listed.
private struct TubeCleanerFeaturesPicker: View {
    @Binding var features: TubeCleanerDeArrowPreference.Features

    private var summary: String {
        features.allEnabled
            ? String(localized: "Features: All")
            : String.localizedStringWithFormat(
                NSLocalizedString("Features: %d off", comment: "Tube Cleaner feature picker label with the number of disabled features"),
                features.disabledCount
            )
    }

    var body: some View {
        Menu {
            Toggle("Chapters", isOn: $features.chapters)
            Toggle("Captions in Native Player", isOn: $features.captions)
            Toggle("Picture in Picture", isOn: $features.pictureInPicture)
            Toggle("Background Playback", isOn: $features.backgroundPlayback)
            Toggle("SponsorBlock", isOn: $features.sponsorBlock)
            Toggle("Resume Where You Left Off", isOn: $features.resumePosition)
            Toggle("Quality and Audio Toolbar", isOn: $features.toolbar)
            Divider()
            Toggle("Hide Shorts", isOn: $features.hideShorts)
            Divider()
            Button("Enable All") {
                let hideShorts = features.hideShorts
                features = TubeCleanerDeArrowPreference.Features()
                features.hideShorts = hideShorts
            }
                .disabled(features.allEnabled)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .imageScale(.small)
                Text(summary)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .accessibilityLabel(summary)
    }
}

private struct PlayerCleanerFeaturesPicker: View {
    @Binding var features: PlayerCleanerPreference.Features

    private var summary: String {
        features.allEnabled
            ? String(localized: "Features: All")
            : String.localizedStringWithFormat(
                NSLocalizedString("Features: %d off", comment: "Tube Cleaner feature picker label with the number of disabled features"),
                features.disabledCount
            )
    }

    var body: some View {
        Menu {
            Toggle("Automatic Picture in Picture", isOn: $features.autoPictureInPicture)
            Toggle("Background Playback", isOn: $features.backgroundPlayback)
            Divider()
            Button("Enable All") { features = PlayerCleanerPreference.Features() }
                .disabled(features.allEnabled)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .imageScale(.small)
                Text(summary)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .accessibilityLabel(summary)
    }
}

private struct DeArrowSettingsPicker: View {
    @Binding var settings: TubeCleanerDeArrowPreference.Settings
    @State private var showingChannels = false

    var body: some View {
        Menu {
            Toggle("Replace Titles", isOn: $settings.replaceTitles)
            Toggle("Replace Thumbnails", isOn: $settings.replaceThumbnails)
            Toggle("Random Frame When No Thumbnail", isOn: $settings.randomThumbnails)
                .disabled(!settings.replaceThumbnails)
            Toggle("Show Original on Hover", isOn: $settings.showOriginalOnHover)
            Divider()
            Button("Original Thumbnail Channels") { showingChannels = true }
            Divider()
            // DeArrow data is CC BY-NC-SA 4.0; the credit link is a license term.
            Link(destination: URL(string: "https://dearrow.ajay.app/")!) {
                Label("About DeArrow", systemImage: "arrow.up.right.square")
            }
            Link("Donate to DeArrow", destination: URL(string: "https://dearrow.ajay.app/donate/")!)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .imageScale(.small)
                Text("Settings")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .accessibilityLabel("Settings")
        .padding(.top, 2)
        .sheet(isPresented: $showingChannels) {
            DeArrowChannelSettingsView(settings: $settings)
        }
    }
}

/// Full-size CodeMirror sheet used by the Add flows and the user list editor.
/// The caller owns the controller; text flows back through `onTextChanged`
/// when the sheet closes.
struct AddUserScriptView: View {
    var userScriptManager: UserScriptManager
    var onScriptAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlInput: String = ""
    @State private var validationState: ValidationState = .idle
    @State private var urlImportError: String?
    private enum URLEntryMode { case single, bulk }
    private struct URLMetadata: Sendable { var title: String?; var description: String? }
    @State private var urlEntryMode: URLEntryMode = .single
    @State private var isReviewingURLs = false
    @State private var isReviewingText = false
    @State private var urlNames: [String: String] = [:]
    @State private var urlDescriptions: [String: String] = [:]
    @State private var urlCategories: [String: FilterListCategory] = [:]
    @State private var urlMetadata: [String: URLMetadata] = [:]
    @State private var urlMetadataTask: Task<Void, Never>?
    @State private var urlMetadataGeneration = 0
    @State private var isFetchingURLMetadata = false
    @State private var isAdding: Bool = false
    @State private var fileImportError: String?
    @State private var editorImportError: String?
    @State private var textInput = ""
    @State private var isShowingEditor = false
    @State private var showingPasteReplacementConfirmation = false
    @State private var pendingPasteText: String?
    @State private var showingFileImporter = false
    @State private var stagedFile: StagedScriptFile?
    @State private var isStagingFile = false
    @State private var stagingGeneration = 0
    @State private var isImportingURLList = false
    @State private var urlListImportGeneration = 0
    @State private var importsURLList = false
    @State private var stagedName = ""
    @State private var stagedDescription = ""
    @State private var selectedCategory: FilterListCategory = .scriptOther
    @State private var editorMetadataState = EditorMetadataAutofillState()
    @State private var editorMetadataRefreshTask: Task<Void, Never>?
    @State private var metadataRefreshGeneration = 0
    @State private var addMode: AddMode = .url
    @StateObject private var editorController: CodeMirrorEditorController
    @FocusState private var urlFieldFocused: Bool
    @FocusState private var textInputFocused: Bool

    enum Kind: String, Identifiable {
        case script, style
        var id: String { rawValue }

        /// A minimal metadata block, so a new script or style starts valid.
        var template: String {
            switch self {
            case .script:
                return "// ==UserScript==\n// @name        New Userscript\n// @match       *://*/*\n// ==/UserScript==\n\n"
            case .style:
                return "/* ==UserStyle==\n@name        New Userstyle\n@namespace   wblock\n==/UserStyle== */\n\n@-moz-document domain(\"example.com\") {\n\n}\n"
            }
        }
    }

    let kind: Kind

    init(userScriptManager: UserScriptManager, kind: Kind = .script, onScriptAdded: @escaping () -> Void) {
        self.userScriptManager = userScriptManager
        self.kind = kind
        self.onScriptAdded = onScriptAdded
        _editorController = StateObject(wrappedValue: CodeMirrorEditorController(text: "", isUserStyle: kind == .style))
    }

    private struct StagedScriptFile {
        let filename: String
        let content: String
        let parsed: UserScript
    }

    private enum AddMode: String, CaseIterable, Identifiable, AddContentMode {
        case url = "URL"
        case text = "Text"
        case file = "File"

        var id: String { rawValue }
        var localizedTitle: LocalizedStringKey { LocalizedStringKey(rawValue) }
        var systemImage: String {
            switch self {
            case .url: return "link"
            case .text: return "text.alignleft"
            case .file: return "doc"
            }
        }
    }

    private var parsedURLs: [URL] {
        UserScriptURLSupport.parseRemoteURLs(from: urlInput)
    }

    var body: some View {
        AddContentSheet(
            title: kind == .style ? "Add Userstyle" : "Add Userscript",
            mode: $addMode,
            isLoading: isAdding,
            submitTitle: LocalizedStringKey(addURLButtonTitle),
            isSubmitDisabled: !canSubmit || isAdding || isImportingURLList,
            onDismiss: { dismiss() },
            onSubmit: submit
        ) { mode in
            modeContent(mode)
        }
        #if os(macOS)
        .onAppear {
            urlFieldFocused = addMode == .url
        }
        .onChangeCompat(of: addMode) { _, newValue in
            urlFieldFocused = newValue == .url
        }
        #endif
        .onChangeCompat(of: urlInput) { _, newValue in
            // Do not rewrite the field while typing: collapsing lines here ate the
            // Return key, which made bulk entry impossible (#642). Paste and
            // submit normalize explicitly; validation tolerates blank lines.
            isReviewingURLs = false
            if urlEntryMode == .single {
                let normalized = FilterListURLSupport.normalizeSingleURLInput(newValue)
                if normalized != newValue { urlInput = normalized; return }
            }
            validateInput(newValue)
            fetchURLMetadata()
        }
        .onChangeCompat(of: urlEntryMode) { _, mode in
            urlListImportGeneration += 1
            isImportingURLList = false
            isReviewingURLs = false
            if mode == .single { urlInput = FilterListURLSupport.normalizeSingleURLInput(urlInput) }
            validateInput(urlInput)
            fetchURLMetadata()
        }
        .onChangeCompat(of: addMode) { _, mode in
            urlListImportGeneration += 1
            isImportingURLList = false
            if mode == .text { scheduleEditorMetadataRefresh() }
            if mode == .url { fetchURLMetadata() } else {
                urlMetadataTask?.cancel()
                urlMetadataGeneration += 1
                isFetchingURLMetadata = false
            }
        }
        .onChangeCompat(of: textInput) { _, _ in
            isReviewingText = false
            guard addMode == .text else { return }
            scheduleEditorMetadataRefresh()
        }
        .onChangeCompat(of: editorController.documentRevision) { _, _ in
            syncTextFromEditor()
        }
        .onChangeCompat(of: stagedName) { _, newValue in
            guard addMode == .text else { return }
            editorMetadataState.noteNameEdit(newValue)
        }
        .onChangeCompat(of: stagedDescription) { _, newValue in
            guard addMode == .text else { return }
            editorMetadataState.noteDescriptionEdit(newValue)
        }
        .onDisappear {
            editorMetadataRefreshTask?.cancel()
            urlMetadataTask?.cancel()
        }
        .alert("Replace Existing Content?", isPresented: $showingPasteReplacementConfirmation) {
            Button("Cancel", role: .cancel) { pendingPasteText = nil }
            Button("Replace", role: .destructive) {
                if let pendingPasteText {
                    replaceEditorText(with: pendingPasteText)
                }
                pendingPasteText = nil
            }
        } message: {
            Text("Pasting will replace the existing content.")
        }
        .sheet(isPresented: $isShowingEditor) {
            SourceEditorSheet(title: kind == .style ? "Style Content" : "Script Content", editorController: editorController, onDone: { text in
                applyEditorText(text)
                return nil
            }, onPaste: pasteScriptFromClipboard)
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: importsURLList ? [.plainText, .text] : allowedImportTypes) { result in
            switch result {
            case .success(let url):
                if importsURLList { importURLList(from: url) } else { stageFile(at: url) }
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    fileImportError = error.localizedDescription
                }
            }
        }
    }
    @ViewBuilder
    private func modeContent(_ mode: AddMode) -> some View {
        switch mode {
        case .url:
            if isReviewingURLs {
                Section {
                    AddContentBackButton {
                        isReviewingURLs = false
                        urlMetadataTask?.cancel()
                        isFetchingURLMetadata = false
                    }
                    if isFetchingURLMetadata { ProgressView().controlSize(.small) }
                } footer: {
                    validationMessage
                }
                ForEach(parsedURLs, id: \.absoluteString) { url in
                    let key = url.absoluteString
                    AddContentURLMetadataSection(
                        url: url,
                        name: Binding(get: { urlNames[key] ?? automaticURLName(for: url) }, set: { urlNames[key] = $0 }),
                        description: Binding(get: { urlDescriptions[key] ?? urlMetadata[key]?.description ?? "" }, set: { urlDescriptions[key] = $0 }),
                        category: Binding(get: { urlCategories[key] ?? selectedCategory }, set: { urlCategories[key] = $0 }),
                        categories: FilterListCategory.userScriptCategories,
                        categoryName: { $0.userScriptCategoryName }
                    ) { EmptyView() }
                }
            } else {
                Section {
                    Picker("URL entry mode", selection: $urlEntryMode) {
                        Text("Single URL").tag(URLEntryMode.single)
                        Text("Bulk URLs").tag(URLEntryMode.bulk)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(isAdding)
                    urlInputEditor
                } footer: {
                    validationMessage
                }
            }
        case .text:
            if isReviewingText {
                Section {
                    AddContentBackButton { isReviewingText = false }
                }
                Section { userScriptMetaFields } footer: { AddContentNote(error: editorImportError) }
            } else {
                AddContentSourceSection(title: kind == .style ? "Style Content" : "Script Content",
                    placeholder: kind == .style
                        ? "Paste or write a userstyle with a /* ==UserStyle== */ metadata block."
                        : "Paste or write a userscript with a // ==UserScript== metadata block.",
                    isEmpty: textInput.isEmpty, isDisabled: isAdding,
                    onPaste: pasteScriptFromClipboard, onOpenEditor: openEditorSheet) {
                        TextEditor(text: $textInput)
                            .hideEditorBackgroundCompat()
                            .autocorrectionDisabled()
                            .focused($textInputFocused)
                            .accessibilityLabel(Text("Script Content"))
                    } footer: {
                        AddContentNote(text: metadataRequirementText, error: editorImportError)
                    }
            }
        case .file:
            Section {
                AddContentFileSelectionButton(
                    filename: stagedFile?.filename,
                    isLoading: isStagingFile,
                    isDisabled: isAdding
                ) {
                    importsURLList = false
                    showingFileImporter = true
                    fileImportError = nil
                }
                if stagedFile != nil { userScriptMetaFields }
            } footer: {
                AddContentNote(text: "Local imports won't auto-update; re-import to replace.", error: fileImportError)
            }
        }
    }

    private var metadataRequirementText: LocalizedStringKey {
        "Include the // ==UserScript== metadata block (or /* ==UserStyle== */ for userstyles) so wBlock can read the name and URL patterns."
    }

    private var userScriptMetaFields: some View {
        AddContentMetadataFields(name: $stagedName, description: $stagedDescription,
                                 category: $selectedCategory, categories: FilterListCategory.userScriptCategories,
                                 categoryName: { $0.userScriptCategoryName })
    }

    private var addURLButtonTitle: String {
        if (addMode == .url && !isReviewingURLs) || (addMode == .text && !isReviewingText) { return "Next" }
        return addMode == .url && parsedURLs.count > 1 ? "Add URLs" : "Add"
    }

    private func fetchURLMetadata() {
        urlMetadataTask?.cancel()
        urlMetadataGeneration += 1
        let generation = urlMetadataGeneration
        guard isReviewingURLs else { isFetchingURLMetadata = false; return }
        let targets = parsedURLs.filter { urlMetadata[$0.absoluteString] == nil }
        guard !targets.isEmpty else { isFetchingURLMetadata = false; return }
        isFetchingURLMetadata = true
        urlMetadataTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, generation == urlMetadataGeneration else { return }
            await boundedConcurrentForEach(targets, maxConcurrent: 4, operation: { url in
                let metadata = try? await RemoteFilterListMetadataLoader.fetch(from: url, userscript: true)
                return (url, URLMetadata(title: metadata?.title, description: metadata?.description))
            }, onResult: { url, metadata in
                guard !Task.isCancelled, generation == urlMetadataGeneration else { return }
                urlMetadata[url.absoluteString] = metadata
            })
            if generation == urlMetadataGeneration { isFetchingURLMetadata = false }
        }
    }

    private func automaticURLName(for url: URL) -> String {
        let title = urlMetadata[url.absoluteString]?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? UserScriptURLSupport.displayName(forRemoteURL: url) : title
    }

    private var urlInputEditor: some View {
        AddContentURLInput(
            text: $urlInput,
            isFocused: $urlFieldFocused,
            isBulk: urlEntryMode == .bulk,
            placeholder: Text(verbatim: "https://example.com/script.user.js"),
            label: urlEntryMode == .single ? "URL" : "URLs",
            isDisabled: isAdding,
            onPaste: pasteFromClipboard,
            pasteTitle: urlEntryMode == .single ? "Paste URL" : "Paste URLs",
            onImportFile: { importsURLList = true; showingFileImporter = true },
            isImportingFile: isImportingURLList
        )
    }

    private var urlValidationFeedback: ValidationState {
        if let urlImportError { return .invalid(urlImportError) }
        return validationState
    }

    private var validationMessage: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                switch urlValidationFeedback {
                case .idle:
                    Text("wBlock will fetch and enable the script automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .invalid(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .valid:
                    Text("Content will be checked when you tap Add.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: validationState)
    }


    private var canSubmit: Bool {
        if isAdding || (addMode == .url && isReviewingURLs && isFetchingURLMetadata) { return false }
        switch addMode {
        case .url:
            if case .valid = validationState { return true }
            return false
        case .text:
            return !textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file:
            return !isStagingFile
                && stagedFile != nil
                && !stagedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func submit() {
        switch addMode {
        case .url:
            guard case .valid(let urls) = validationState else { return }
            if !isReviewingURLs {
                isReviewingURLs = true
                urlFieldFocused = false
                fetchURLMetadata()
                return
            }

            isAdding = true
            urlImportError = nil

            Task(priority: .userInitiated) {
                for url in urls {
                    await ConcurrentLogManager.shared.info(.userScript, LocalizedStrings.text("Adding new userscript from URL"), metadata: ["url": url.absoluteString])
                    let key = url.absoluteString
                    let name = ImportMetadataReview.userProvided(urlNames[key], automatic: automaticURLName(for: url))
                    let description = ImportMetadataReview.userProvided(urlDescriptions[key], automatic: urlMetadata[key]?.description)
                    if let error = await userScriptManager.addUserScript(from: url, nameOverride: name, descriptionOverride: description, category: urlCategories[key] ?? selectedCategory) {
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        await ConcurrentLogManager.shared.error(.userScript, LocalizedStrings.text("Failed to add userscript from URL"), metadata: ["url": url.absoluteString, "error": message])
                        await MainActor.run {
                            urlImportError = message
                            isAdding = false
                        }
                        return
                    }
                    await ConcurrentLogManager.shared.info(.userScript, LocalizedStrings.text("Successfully added userscript from URL"), metadata: ["url": url.absoluteString])
                }

                await MainActor.run {
                    isAdding = false
                    onScriptAdded()
                    dismiss()
                }
            }
        case .text:
            if !isReviewingText {
                _ = editorMetadataOverrides(for: textInput)
                isReviewingText = true
                return
            }
            addScriptFromText()
        case .file:
            guard let stagedFile else { return }
            isAdding = true
            fileImportError = nil
            Task(priority: .userInitiated) {
                let error = await userScriptManager.addUserScript(
                    fromStagedImport: stagedFile.parsed,
                    nameOverride: stagedName,
                    descriptionOverride: stagedDescription,
                    category: selectedCategory
                )
                if let error {
                    await MainActor.run {
                        fileImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        isAdding = false
                    }
                } else {
                    await MainActor.run {
                        isAdding = false
                        onScriptAdded()
                        dismiss()
                    }
                }
            }
        }
    }

    private var allowedImportTypes: [UTType] {
        var types: [UTType] = []

        types.append(UTType.javaScript)

        // Add fallback for .js extension
        if let jsExt = UTType(filenameExtension: "js") {
            types.append(jsExt)
        }

        let userJsTypes = UTType.types(tag: "user.js", tagClass: .filenameExtension, conformingTo: nil)
        if !userJsTypes.isEmpty {
            types.append(contentsOf: userJsTypes)
        } else if let userJsExt = UTType(filenameExtension: "user.js", conformingTo: .data) {
            types.append(userJsExt)
        }

        // Userstyles (.user.css / .css and offline compiler formats)
        types.append(UTType(filenameExtension: "css") ?? .plainText)
        types.append(UTType(filenameExtension: "less") ?? .plainText)
        for fileExtension in ["sass", "scss", "styl", "pcss"] {
            types.append(UTType(filenameExtension: fileExtension) ?? .plainText)
        }

        let userCssTypes = UTType.types(tag: "user.css", tagClass: .filenameExtension, conformingTo: nil)
        if !userCssTypes.isEmpty {
            types.append(contentsOf: userCssTypes)
        } else if let userCssExt = UTType(filenameExtension: "user.css", conformingTo: .data) {
            types.append(userCssExt)
        }

        return types
    }

    private func addScriptFromText() {
        isAdding = true
        editorImportError = nil

        Task(priority: .userInitiated) {
            let content = textInput
            let metadata = editorMetadataOverrides(for: content)
            let error = await userScriptManager.addUserScript(
                fromSourceContent: content,
                nameOverride: metadata.name,
                descriptionOverride: metadata.description,
                category: selectedCategory
            )

            if let error {
                await MainActor.run {
                    editorImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isAdding = false
                }
            } else {
                await ConcurrentLogManager.shared.info(.userScript, LocalizedStrings.text("Added userscript from editor"))

                await MainActor.run {
                    isAdding = false
                    onScriptAdded()
                    dismiss()
                }
            }
        }
    }

    private func importURLList(from url: URL) {
        urlListImportGeneration += 1
        let generation = urlListImportGeneration
        // Drop anything prepared from the previous input before the async read.
        isReviewingURLs = false
        urlMetadataTask?.cancel()
        isFetchingURLMetadata = false
        isImportingURLList = true
        urlImportError = nil
        let didAccess = url.startAccessingSecurityScopedResource()
        Task { @MainActor in
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try await Task.detached(priority: .userInitiated) {
                    try UserScriptURLSupport.urlListText(fromFile: url)
                }.value
                guard generation == urlListImportGeneration else { return }
                urlInput = UserScriptURLSupport.appendingPastedURLs(text, to: urlInput)
                isImportingURLList = false
            } catch {
                guard generation == urlListImportGeneration else { return }
                isImportingURLList = false
                urlImportError = error.localizedDescription
            }
        }
    }

    private func stageFile(at url: URL) {
        stagingGeneration += 1
        let generation = stagingGeneration
        isStagingFile = true
        fileImportError = nil
        let didAccess = url.startAccessingSecurityScopedResource()

        Task { @MainActor in
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try UserScriptManager.stageUserScriptImport(fromLocalFile: url)
                }.value

                guard generation == stagingGeneration else { return }
                stagedFile = StagedScriptFile(
                    filename: url.lastPathComponent,
                    content: parsed.content,
                    parsed: parsed
                )
                let metadataName = parsed.name.trimmingCharacters(in: .whitespacesAndNewlines)
                stagedName = metadataName.isEmpty
                    ? UserScriptURLSupport.displayName(forFilename: url.lastPathComponent)
                    : metadataName
                stagedDescription = parsed.description.trimmingCharacters(in: .whitespacesAndNewlines)
                selectedCategory = .scriptOther
                isStagingFile = false
            } catch {
                guard generation == stagingGeneration else { return }
                isStagingFile = false
                fileImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func scheduleEditorMetadataRefresh() {
        editorMetadataRefreshTask?.cancel()
        metadataRefreshGeneration &+= 1
        let generation = metadataRefreshGeneration
        let editorRevision = editorController.documentRevision
        let readsEditor = isShowingEditor
        editorMetadataRefreshTask = Task { @MainActor in
            // CodeMirror can emit one revision per keystroke. Debounce the scan and
            // parse only the metadata-sized prefix, never the whole source document.
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled,
                  generation == metadataRefreshGeneration,
                  addMode == .text
            else { return }

            let content: String
            if readsEditor {
                guard editorController.documentRevision == editorRevision else { return }
                content = await editorController.currentText()
                guard !Task.isCancelled,
                      generation == metadataRefreshGeneration,
                      editorController.documentRevision == editorRevision
                else { return }
            } else {
                content = textInput
                guard content == textInput else { return }
            }

            guard generation == metadataRefreshGeneration else { return }
            _ = editorMetadataOverrides(for: content)
        }
    }

    private func editorMetadataOverrides(for content: String) -> (name: String, description: String) {
        let boundedContent = content
            .components(separatedBy: .newlines)
            .prefix(120)
            .joined(separator: "\n")
            .prefix(16_000)
        var parsed = UserScript(
            name: "",
            content: String(boundedContent)
        )
        parsed.parseMetadata()

        let values = editorMetadataState.autofill(
            name: parsed.name,
            description: parsed.description,
            currentName: stagedName,
            currentDescription: stagedDescription
        )
        if stagedName != values.name { stagedName = values.name }
        if stagedDescription != values.description { stagedDescription = values.description }
        return values
    }

    private func validateInput(_ newValue: String) {
        urlImportError = nil
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            validationState = .idle
            return
        }

        let urls = UserScriptURLSupport.parseRemoteURLs(from: trimmed)
        guard !urls.isEmpty else {
            validationState = .invalid(String(localized: "Provide a valid http:// or https:// link ending in .js, .user.js, .user.css, .less, .sass, .scss, .styl, or .pcss"))
            return
        }

        validationState = .valid(urls)
    }

    private func pasteFromClipboard() {
        #if os(iOS)
        let string = UIPasteboard.general.string
        #elseif os(macOS)
        let string = NSPasteboard.general.string(forType: .string)
        #endif
        guard let string else { return }
        urlInput = urlEntryMode == .single
            ? FilterListURLSupport.normalizeSingleURLInput(string)
            : UserScriptURLSupport.appendingPastedURLs(string, to: urlInput)
    }

    private func pasteScriptFromClipboard() {
        #if os(iOS)
        guard let string = UIPasteboard.general.string else { return }
        #elseif os(macOS)
        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        #endif

        Task { @MainActor in
            let currentText = isShowingEditor ? await editorController.currentText() : textInput
            if currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                replaceEditorText(with: string)
            } else {
                pendingPasteText = string
                showingPasteReplacementConfirmation = true
            }
        }
    }

    private func replaceEditorText(with string: String) {
        editorImportError = nil
        textInput = string
        editorController.replaceText(string, markClean: true)
        scheduleEditorMetadataRefresh()
        DispatchQueue.main.async {
            if isShowingEditor {
                editorController.focus()
            } else {
                textInputFocused = true
            }
        }
    }

    private func openEditorSheet() {
        addMode = .text
        // An empty editor starts from the chosen kind's metadata block.
        editorController.replaceText(textInput.isEmpty ? kind.template : textInput, markClean: textInput.isEmpty == false)
        isShowingEditor = true
    }

    private func applyEditorText(_ text: String) {
        textInput = text
        editorController.replaceText(text, markClean: true)
        scheduleEditorMetadataRefresh()
    }

    private func syncTextFromEditor() {
        guard isShowingEditor else { return }
        Task { @MainActor in
            let text = await editorController.currentText()
            guard text != textInput else { return }
            textInput = text
            scheduleEditorMetadataRefresh()
        }
    }

    private enum ValidationState: Equatable {
        case idle
        case invalid(String)
        case valid([URL])
    }
}
