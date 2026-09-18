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
        [.scriptBlocking, .scriptFunctionality, .scriptAppearance, .scriptOther]
    }

    var userScriptCategoryName: String {
        (isUserScriptOnly ? self : .scriptOther).localizedName
    }
}

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private func isIntegratedUserScript(
    _ script: UserScript,
    isBuiltIn: Bool,
    builtInDisplayRole: BuiltInUserScriptDisplayRole?
) -> Bool {
    isBuiltIn && builtInDisplayRole == .functionality
        && (script.name == "Dark Reader" || script.name == "Tube Cleaner" || script.name == "Player Cleaner")
}

private struct UserScriptListItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let localizedDisplayName: String
    let localizedDisplayDescription: String
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
    let isIntegrated: Bool
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
        url = script.url
        updateURL = script.updateURL
        isEnabled = script.isEnabled
        version = script.version
        lastUpdated = script.lastUpdated
        isLocal = script.isLocal
        self.isDownloaded = isDownloaded
        updatesAutomatically = script.updatesAutomatically
        isUserStyle = script.isUserStyle
        category = script.category
        displayCategory = UserScriptDisplayCategorySupport.category(
            isUserStyle: script.isUserStyle,
            builtInRole: builtInDisplayRole,
            persistedCategory: script.category
        )
        self.isBuiltIn = isBuiltIn
        isIntegrated = isIntegratedUserScript(
            script,
            isBuiltIn: isBuiltIn,
            builtInDisplayRole: builtInDisplayRole
        )
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

private struct EditorMetadataAutofillState: Equatable {
    private(set) var lastAutofilledName = ""
    private(set) var lastAutofilledDescription = ""
    private(set) var nameWasManuallyEdited = false
    private(set) var descriptionWasManuallyEdited = false

    mutating func autofill(
        name metadataName: String,
        description metadataDescription: String,
        currentName: String,
        currentDescription: String
    ) -> (name: String, description: String) {
        let name = metadataName.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = metadataDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameWasManuallyEdited {
            lastAutofilledName = name
        }
        if !descriptionWasManuallyEdited {
            lastAutofilledDescription = description
        }
        return (
            nameWasManuallyEdited ? currentName : lastAutofilledName,
            descriptionWasManuallyEdited ? currentDescription : lastAutofilledDescription
        )
    }

    mutating func noteNameEdit(_ value: String) {
        if value != lastAutofilledName { nameWasManuallyEdited = true }
    }

    mutating func noteDescriptionEdit(_ value: String) {
        if value != lastAutofilledDescription { descriptionWasManuallyEdited = true }
    }
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
    let hasPendingChanges: Bool
    let isApplyingChanges: Bool
    let onApplyChanges: () -> Void
    let onForceApplyChanges: () -> Void
    let tabSelection: AppTabSelection
    /// Incremented by ContentView for ⌘⇧N / ⌘L; see `handledAddRequest`.
    let addRequest: Int
    let searchRequest: Int
    let onRefresh: () async -> Void
    /// Scoped manual checks (#657) exposed from the Apply button's context menu.
    var onCheckFilterUpdates: () -> Void = {}
    var onCheckScriptUpdates: () -> Void = {}
    var failedReloadCount: Int = 0
    var onRetryFailedReloads: () -> Void = {}

    @State private var scripts: [UserScriptListItem] = []
    @AppStorage("userScriptDisplayOrder") private var scriptDisplayOrder = Data()
    @State private var showingAddScriptSheet = false
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

    private var applyChangesToolbarButton: some View {
        ApplyChangesHoldButton(
            isDisabled: isApplyingChanges,
            hasPendingChanges: hasPendingChanges,
            onTap: onApplyChanges,
            onForceApply: onForceApplyChanges
        ) {
            if hasPendingChanges {
                Text("Apply").fontWeight(.semibold)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        #if os(macOS)
        .contextMenu {
            Button("Check for Filter Updates", action: onCheckFilterUpdates)
            Button("Check for Userscript Updates", action: onCheckScriptUpdates)
            Divider()
            Button("Apply Without Checking for Updates", action: onForceApplyChanges)
                .disabled(isApplyingChanges)
            if failedReloadCount > 0 {
                Button(action: onRetryFailedReloads) {
                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("Retry %d failed extension(s)", comment: "Summary button that reloads only the blockers that failed"),
                            failedReloadCount
                        )
                    )
                }
                .disabled(isApplyingChanges)
            }
        }
        #endif
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
              let category = FilterListCategory(rawValue: category.rawValue) else { return }
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
        .sheet(isPresented: $showingAddScriptSheet, onDismiss: {
            refreshScripts()
        }) {
            AddUserScriptView(userScriptManager: userScriptManager, onScriptAdded: {
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
            showingAddScriptSheet = true
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
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if #unavailable(iOS 26.0) {
                    Button {
                        showSearch = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }
                Button {
                    showingAddScriptSheet = true
                } label: {
                    Label("Add Userscript or Userstyle", systemImage: "plus")
                }
                Button {
                    showOnlyEnabled.toggle()
                    ProtobufDataManager.shared.setUserScriptShowEnabledOnly(showOnlyEnabled)
                } label: {
                    Label(
                        "Show Enabled Only",
                        systemImage: showOnlyEnabled
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                }
            }
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
        .modifier(macScriptsToolbar)
        #endif
    }

    #if os(macOS)
    private var macScriptSections: [MacListSection] {
        UserScriptDisplayCategory.allCases.map { category in
            let section = UserScriptDisplaySection(id: category, scripts: displayedScripts.filter { $0.displayCategory == category })
            return MacListSection(id: category.id, header: AnyView(displaySectionHeader(section)),
                                  rows: section.scripts.map { script in MacListRow(script.id) { scriptRowView(script: script) } })
        }
    }

    private func commitScriptMove(_ move: MacListMove) -> Bool {
        guard let category = UserScriptDisplayCategory(rawValue: move.sectionID),
              let persisted = FilterListCategory(rawValue: category.rawValue),
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

    private var macScriptsToolbar: some ViewModifier {
        MacActionsToolbar(isSearchExpanded: showSearch, hasPendingChanges: hasPendingChanges) {
            Button {
                showingAddScriptSheet = true
            } label: {
                Label("Add Userscript or Userstyle", systemImage: "plus")
            }
        } apply: {
            applyChangesToolbarButton
        } filter: {
            Button {
                showOnlyEnabled.toggle()
                ProtobufDataManager.shared.setUserScriptShowEnabledOnly(showOnlyEnabled)
            } label: {
                Label(
                    "Show Enabled Only",
                    systemImage: showOnlyEnabled
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
            }
        } search: {
            ToolbarSearchField(
                text: $searchText,
                isExpanded: $showSearch,
                prompt: "Search scripts"
            )
        }
    }
    #endif

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
        return HStack(spacing: compact ? 8 : 12) {
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
        #if os(iOS)
        .fixedSize(horizontal: false, vertical: true)
        #endif
        .padding(.horizontal)
    }

    private func displaySectionHeader(_ section: UserScriptDisplaySection) -> some View {
        ListCategoryHeader(title: section.title, info: { selectedCategoryInfo = section.id }, anchorID: section.id.id)
    }

    private func scriptInfoContent(_ selection: SelectedUserScript) -> some View {
        UserScriptInfoView(
            scriptId: selection.id, userScriptManager: userScriptManager,
            onChangeDisplayCategory: { moveScript(selection.id, to: $0) },
            onDownload: {
                if let item = scripts.first(where: { $0.id == selection.id }) { downloadScript(item) }
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
                        persistedCategory: script.category
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
                persistedCategory: script.category
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
    private func downloadScript(_ script: UserScriptListItem) {
        guard !script.isLocal, !script.isDownloaded,
              !downloadingScriptIDs.contains(script.id),
              let managedScript = userScriptManager.userScript(withId: script.id)
        else { return }
        downloadingScriptIDs.insert(script.id)
        Task {
            await ConcurrentLogManager.shared.info(
                .userScript, LocalizedStrings.text("Downloading userscript"), metadata: ["script": script.name])
            _ = await userScriptManager.downloadUserScript(managedScript)
            await MainActor.run {
                downloadingScriptIDs.remove(script.id)
                refreshScripts()
            }
        }
    }

    private func applyEnabledState(for script: UserScriptListItem, newValue: Bool) {
        guard let latestState = userScriptManager.userScriptToggleState(for: script.id),
              latestState.desired != newValue
        else { return }
        let managedScript = userScriptManager.userScript(withId: script.id)
        let shouldDownloadBeforeEnabling =
            newValue && !(managedScript?.isDownloaded ?? script.isDownloaded)
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
                downloadingScriptIDs.remove(script.id)
                refreshScripts()
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
                Text(ContentRowMetadata.summary([
                    NSLocalizedString(
                        script.isIntegrated ? "Integrated" : (script.isUserStyle ? "Userstyle" : "Userscript"),
                        comment: "Content type"
                    ),
                    ContentRowMetadata.versionLabel(script.version),
                    ContentRowMetadata.updatedLabel(
                        UserScriptModifiedStore.date(for: script.url) ?? script.lastUpdated
                    ),
                ]))
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
                    name: script.name, action: { downloadScript(script) }
                )
            } else {
                Toggle("", isOn: Binding(
                    get: { displayedEnabled },
                    set: { newValue in
                        if newValue, script.isBeta, !BetaUserscriptWarning.hasAcknowledged {
                            pendingBetaEnableScript = script
                            return
                        }
                        applyEnabledState(for: script, newValue: newValue)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
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
            Button {
                selectedScriptInfo = SelectedUserScript(id: script.id, action: .info)
            } label: {
                Label("Info", systemImage: "info.circle")
            }
        }
        if actions.contains(.settings) {
            Button {
                selectedScriptSettings = SelectedUserScript(id: script.id, action: .settings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        if actions.contains(.viewContent) {
            Button {
                selectedScript = SelectedUserScript(id: script.id, action: .viewContent)
            } label: {
                Label("View Content", systemImage: "doc.text")
            }
        }
        if actions.contains(.editContent) {
            Button {
                selectedScript = SelectedUserScript(id: script.id, action: .editContent)
            } label: {
                Label("Edit Content", systemImage: "pencil")
            }
        }
        if actions.contains(.editInfo) {
            Button {
                selectedScript = SelectedUserScript(id: script.id, action: .editInfo)
            } label: {
                Label("Edit Info", systemImage: "square.and.pencil")
            }
        }
        if actions.contains(.download) {
            Button {
                downloadScript(script)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .disabled(downloadingScriptIDs.contains(script.id))
        }
        Picker(selection: Binding(
            get: { script.displayCategory },
            set: { category in
                moveScript(script.id, to: category)
            }
        )) {
            ForEach(UserScriptDisplayCategory.allCases) { category in
                Text(LocalizedStringKey(category.rawValue)).tag(category)
            }
        } label: {
            Label("Move to", systemImage: "folder")
        }
        if actions.contains(.deleteScript),
           let managedScript = userScriptManager.userScript(withId: script.id) {
            Button(role: .destructive) {
                removeScript(managedScript, name: script.name)
            } label: {
                Label(
                    script.isUserStyle ? "Delete Style" : "Delete Script",
                    systemImage: "trash"
                )
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("No Userscripts")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Add userscripts and userstyles to customize your browsing experience")
                .font(.body)
                .foregroundStyle(.secondary)
            Button {
                showingAddScriptSheet = true
            } label: {
                Label("Add Userscript or Userstyle", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.7))
            Text("No matching userscripts")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UserScriptInfoSidebar Subviews

private struct ScriptNameAndDescriptionView: View {
    let script: UserScript
    let isBeta: Bool
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                // The badge shares the title's first baseline so it reads as
                // part of the name. Done stays pinned to the top corner.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(script.localizedDisplayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if isBeta {
                        Badge(text: "Beta", color: .orange)
                    }
                }
                if let onClose {
                    Spacer(minLength: 8)
                    SheetDoneButton(action: onClose)
                }
            }
            if !script.localizedDisplayDescription.isEmpty {
                Text(script.localizedDisplayDescription).font(.body).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

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

private struct ScriptMatchPatternsView: View {
    let script: UserScript
    @Binding var isPatternsExpanded: Bool

    /// Userstyles persist serialized @-moz-document conditions in `matches`;
    /// render them in a human-readable form instead of the storage format.
    private func displayPattern(_ pattern: String) -> String {
        guard script.isUserStyle else { return pattern }
        if pattern == "global" {
            return LocalizedStrings.text("All websites", comment: "Userstyle condition that applies everywhere")
        }
        for prefix in ["domain:", "url-prefix:", "url:", "regexp:"] where pattern.hasPrefix(prefix) {
            let value = String(pattern.dropFirst(prefix.count))
            return prefix == "url-prefix:" ? value + "…" : value
        }
        return pattern
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPatternsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(
                        script.isUserStyle
                            ? LocalizedStrings.format(
                                "Applies To (%d)",
                                comment: "Userstyle condition section title",
                                script.matches.count
                            )
                            : LocalizedStrings.format(
                                "URL Patterns (%d)",
                                comment: "Userscript URL pattern section title",
                                script.matches.count
                            )
                    )
                        .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: isPatternsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain).noFocusRingCompat().padding(.horizontal, 8).padding(.vertical, 6).cornerRadius(6).onHover { _ in }

            if isPatternsExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(script.matches.indices, id: \.self) { indexInForEach in
                            ScriptMatchPatternRowView(
                                index: indexInForEach,
                                total: script.matches.count,
                                pattern: displayPattern(script.matches[indexInForEach])
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5), lineWidth: 0.5))
            }
        }
    }
}


struct UserScriptSettingsView: View {
    let scriptID: UUID
    @ObservedObject var userScriptManager: UserScriptManager

    var body: some View {
        if let script = userScriptManager.userScript(withId: scriptID) {
            ContentSettingsView(name: script.localizedDisplayName) {
                UserScriptWebsiteExceptionsView(scriptID: scriptID, userScriptManager: userScriptManager)
                if !script.isLocal && script.resolvedDownloadURL != nil {
                    ScriptUpdateSettingsView(updatesAutomatically: script.updatesAutomatically) { enabled in
                        Task { await userScriptManager.setUserScript(script, updatesAutomatically: enabled) }
                    }
                }
            }
        } else {
            Text("Unable to load script")
        }
    }
}

private struct ScriptUpdateSettingsView: View {
    let updatesAutomatically: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { updatesAutomatically }, set: onChange)) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Automatic Updates")
                Text("Turn this off to keep the current version when wBlock updates scripts in bulk or on a schedule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        // A shape background instead of cornerRadius: the latter clips, and on
        // iOS 26 the switch's glass thumb extends past the row's bounds.
        .background(Color.orange.opacity(updatesAutomatically ? 0 : 0.08), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, -8)
    }
}


struct UserScriptInfoSidebar: View {
    let script: UserScript
    let contentLength: Int
    @Binding var isPatternsExpanded: Bool
    let formatFileSize: (Int) -> String
    let isBuiltIn: Bool
    let builtInDisplayRole: BuiltInUserScriptDisplayRole?
    let isBeta: Bool
    let onCategoryChanged: (FilterListCategory) -> Void
    var onClose: (() -> Void)? = nil
    /// False when the sheet shows a category picker in its action list.
    var showsBuiltInCategory = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let metadata = ContentInfoMetadata.userscript(script.content)
            VStack(alignment: .leading, spacing: 8) {
                ScriptNameAndDescriptionView(script: script, isBeta: isBeta, onClose: onClose)
                ScriptStatusBadgesView(script: script, isDownloaded: contentLength > 0, isBuiltIn: isBuiltIn)
            }
            VStack(alignment: .leading, spacing: 6) {
                InfoMetadataRow(title: "Type", value: NSLocalizedString(
                    script.isUserStyle ? "Userstyle" : (isIntegratedUserScript(script, isBuiltIn: isBuiltIn, builtInDisplayRole: builtInDisplayRole) ? "Integrated" : "Userscript"),
                    comment: "Content type"
                ), color: script.isUserStyle ? .purple : .red)
                if isBuiltIn {
                    if showsBuiltInCategory {
                    InfoMetadataRow(title: "Category", value: NSLocalizedString(UserScriptDisplayCategorySupport.category(
                        isUserStyle: script.isUserStyle, builtInRole: builtInDisplayRole, persistedCategory: script.category
                    ).rawValue, comment: "Userscript category"))
                    }
                } else {
                    ContentCategoryPicker(selection: Binding(
                        get: { script.category.isUserScriptOnly ? script.category : .scriptOther },
                        set: onCategoryChanged
                    ), categories: FilterListCategory.userScriptCategories)
                }
                InfoMetadataRow(title: "Author", value: metadata.author ?? String(localized: "Not provided"))
                InfoMetadataRow(
                    title: "Homepage",
                    value: metadata.homepage?.absoluteString ?? String(localized: "Not provided"),
                    url: metadata.homepage
                )
                if !script.version.isEmpty { InfoMetadataRow(title: "Version", value: script.version) }
                if script.url != nil { ScriptURLView(script: script) }
                if contentLength > 0 { InfoMetadataRow(title: "Size", value: formatFileSize(contentLength)) }
            }
            if !script.matches.isEmpty { ScriptMatchPatternsView(script: script, isPatternsExpanded: $isPatternsExpanded) }
        }
    }
}

struct UserScriptInfoView: View {
    let scriptId: UUID
    var userScriptManager: UserScriptManager
    /// iOS only. Rows have no overflow menu there, so the sheet hosts the
    /// secondary actions macOS keeps in the context menu.
    var onChangeDisplayCategory: ((UserScriptDisplayCategory) -> Void)? = nil
    var onDownload: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var script: UserScript?
    @State private var isPatternsExpanded = false
    @State private var isLoading = true
    @State private var showingMetadataEditor = false
    @State private var showingSettings = false
    @State private var showingSource = false
    @State private var confirmingDelete = false

    var body: some View {
        Group {
            if let script {
                #if os(iOS)
                // The sidebar shows the name as its heading with the close
                // button beside it; a navigation bar on top read as a duplicate
                // title (#628) and left an empty row above the content (#793).
                ScrollView {
                    UserScriptInfoSidebar(
                        script: script,
                        contentLength: script.content.utf8.count,
                        isPatternsExpanded: $isPatternsExpanded,
                        formatFileSize: formatFileSize,
                        isBuiltIn: userScriptManager.isDefaultUserScript(script),
                        builtInDisplayRole: userScriptManager.builtInDisplayRole(for: script),
                        isBeta: userScriptManager.isBeta(for: script),
                        onCategoryChanged: setCategory,
                        onClose: { dismiss() },
                        showsBuiltInCategory: onChangeDisplayCategory == nil
                    )
                    .padding()
                    actionList(for: script)
                        .padding([.horizontal, .bottom])
                }
                #else
                InfoContentScrollView {
                    UserScriptInfoSidebar(
                        script: script,
                        contentLength: script.content.utf8.count,
                        isPatternsExpanded: $isPatternsExpanded,
                        formatFileSize: formatFileSize,
                        isBuiltIn: userScriptManager.isDefaultUserScript(script),
                        builtInDisplayRole: userScriptManager.builtInDisplayRole(for: script),
                        isBeta: userScriptManager.isBeta(for: script),
                        onCategoryChanged: setCategory,
                        onClose: { dismiss() }
                    )
                    .padding(20)
                }
                .frame(width: 460)
                #endif
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Unable to load script")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingMetadataEditor, onDismiss: {
            Task { script = await userScriptManager.userScriptEditorSnapshot(withId: scriptId) }
        }) {
            UserScriptContentView(scriptId: scriptId, userScriptManager: userScriptManager, metadataOnly: true)
        }
        #if os(iOS)
        .sheet(isPresented: $showingSettings) {
            UserScriptSettingsView(scriptID: scriptId, userScriptManager: userScriptManager)
                .infoSheetPresentationCompat()
        }
        .sheet(isPresented: $showingSource, onDismiss: {
            Task { script = await userScriptManager.userScriptEditorSnapshot(withId: scriptId) }
        }) {
            UserScriptContentView(
                scriptId: scriptId, userScriptManager: userScriptManager,
                startsEditing: script.map { !userScriptManager.isDefaultUserScript($0) && $0.isLocal } ?? false
            )
        }
        #endif
        .task(id: scriptId) {
            isLoading = true
            script = await userScriptManager.userScriptEditorSnapshot(withId: scriptId)
            isLoading = false
        }
    }

    #if os(iOS)
    @ViewBuilder
    private func actionList(for script: UserScript) -> some View {
        let isBuiltIn = userScriptManager.isDefaultUserScript(script)
        let actions = ContextMenuActionAvailability.userScriptActions(
            isBuiltIn: isBuiltIn, isLocal: script.isLocal,
            isDownloaded: userScriptManager.hasDownloadedContent(for: script)
        )
        InfoActionList {
            if actions.contains(.settings) {
                InfoActionRow("Settings", systemImage: "gearshape") { showingSettings = true }
            }
            if actions.contains(.viewContent) {
                InfoActionRow("View Content", systemImage: "doc.text") { showingSource = true }
            }
            if actions.contains(.editContent) {
                InfoActionRow("Edit Content", systemImage: "pencil") { showingSource = true }
            }
            if actions.contains(.editInfo) {
                InfoActionRow("Edit Info", systemImage: "square.and.pencil") { showingMetadataEditor = true }
            }
            if actions.contains(.download), let onDownload {
                InfoActionRow("Download", systemImage: "arrow.down.circle") {
                    onDownload()
                    dismiss()
                }
            }
            if isBuiltIn, let onChangeDisplayCategory {
                InfoCategoryRow(
                    selection: Binding(
                        get: {
                            UserScriptDisplayCategorySupport.category(
                                isUserStyle: script.isUserStyle,
                                builtInRole: userScriptManager.builtInDisplayRole(for: script),
                                persistedCategory: script.category
                            )
                        },
                        set: { category in
                            onChangeDisplayCategory(category)
                            Task { self.script = await userScriptManager.userScriptEditorSnapshot(withId: scriptId) }
                        }
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
    #endif

    private func setCategory(_ category: FilterListCategory) {
        guard var currentScript = script, !userScriptManager.isDefaultUserScript(currentScript) else { return }
        currentScript.category = category
        script = currentScript
        Task { await userScriptManager.setUserScript(currentScript, category: category) }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Custom scripts share metadata fields with filters; their local source can
/// also be edited inline or opened in the full source editor.
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
                UserScriptSourceSheet(
                    script: script,
                    initialContent: loadedContent,
                    canEdit: !userScriptManager.isDefaultUserScript(script),
                    metadataOnly: metadataOnly,
                    onSave: { newContent, name, description, category in
                        if script.isLocal && !metadataOnly && newContent != loadedContent,
                           let error = await userScriptManager.saveEditedContent(for: script.id, newContent: newContent) {
                            return error
                        }
                        guard await userScriptManager.setUserScriptMetadataOverrides(
                            for: script.id, name: name, description: description
                        ) else {
                            return String(localized: "Couldn't save the edited source.")
                        }
                        await userScriptManager.setUserScript(script, category: category)
                        return nil
                    }
                )
            } else if isLoadingContent {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(macOS)
                    .frame(width: 1000, height: 700)
                    #endif
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
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

private struct UserScriptSourceSheet: View {
    let script: UserScript
    let initialContent: String
    let canEdit: Bool
    let metadataOnly: Bool
    let onSave: (String, String, String, FilterListCategory) async -> String?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var editorController: CodeMirrorEditorController
    @State private var editedContent: String
    @State private var editedName: String
    @State private var editedDescription: String
    @State private var selectedCategory: FilterListCategory
    @State private var isShowingEditor = false
    @State private var isLineWrappingEnabled = false
    @State private var isSaving = false
    @State private var validationMessage: String?

    init(script: UserScript, initialContent: String, canEdit: Bool, metadataOnly: Bool = false,
         onSave: @escaping (String, String, String, FilterListCategory) async -> String?) {
        self.script = script
        self.initialContent = initialContent
        self.canEdit = canEdit
        self.metadataOnly = metadataOnly
        self.onSave = onSave
        _editorController = StateObject(wrappedValue: CodeMirrorEditorController(text: initialContent, isUserStyle: script.isUserStyle))
        _editedContent = State(initialValue: initialContent)
        _editedName = State(initialValue: script.name)
        _editedDescription = State(initialValue: script.description)
        _selectedCategory = State(initialValue: script.category.isUserScriptOnly ? script.category : .scriptOther)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(script.localizedDisplayName).font(.headline).lineLimit(1)
                Spacer()
                if !canEdit && !metadataOnly {
                    SourceViewerControls(wrapsLines: $isLineWrappingEnabled) { editorController.openSearch() }
                }
                if canEdit {
                    Button("Save") { Task { await saveChanges() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving || !hasChanges || editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                SheetDoneButton { dismiss() }
                    .disabled(isSaving)
            }
            .padding(16)
            Divider()
            if canEdit {
                GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AddContentMetadataFields(name: $editedName, description: $editedDescription,
                            category: $selectedCategory, categories: FilterListCategory.userScriptCategories)
                        if let validationMessage {
                            Text(validationMessage).foregroundStyle(.red).font(.caption)
                        }
                        if !metadataOnly {
                            HStack {
                                (script.isUserStyle ? Text("Style Content") : Text("Script Content"))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if script.isLocal {
                                    Button { pasteContent() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                                    Button {
                                        editorController.replaceText(editedContent, markClean: true)
                                        isShowingEditor = true
                                    } label: { Label("Use Editor", systemImage: "curlybraces") }
                                } else {
                                    SourceViewerControls(wrapsLines: $isLineWrappingEnabled) { editorController.openSearch() }
                                }
                            }
                            if script.isLocal {
                                TextEditor(text: $editedContent)
                                    .font(.system(.body, design: .monospaced))
                                    .disableAutocorrection(true)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    #endif
                                    .frame(minHeight: 260, maxHeight: .infinity)
                            } else {
                                CodeMirrorTextEditor(controller: editorController, isEditable: false,
                                    isLineWrappingEnabled: isLineWrappingEnabled)
                                    .frame(minHeight: 260, maxHeight: .infinity)
                            }
                        }
                    }
                    .padding(20)
                    // Stretch the content to the sheet so the source editor takes
                    // the space under the metadata fields instead of a fixed 260pt.
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .disabled(isSaving)
                }
                }
            } else {
                CodeMirrorTextEditor(controller: editorController, isEditable: false,
                    isLineWrappingEnabled: isLineWrappingEnabled)
            }
        }
        #if os(macOS)
        .frame(width: metadataOnly ? 460 : 1000, height: metadataOnly ? 360 : 700)
        #endif
        .interactiveDismissDisabled(isSaving)
        .sheet(isPresented: $isShowingEditor) {
            CodeEditorSheet(editorController: editorController, onTextChanged: { editedContent = $0 }, onPaste: {
                if let text = clipboardText { editorController.replaceText(text) }
            })
        }
    }

    private var clipboardText: String? {
        #if os(iOS)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }

    private func pasteContent() {
        if let text = clipboardText { editedContent = text }
    }

    private var hasChanges: Bool {
        editedContent != initialContent || editedName != script.name || editedDescription != script.description
            || selectedCategory != (script.category.isUserScriptOnly ? script.category : .scriptOther)
    }

    @MainActor private func saveChanges() async {
        isSaving = true
        let error = await onSave(editedContent, editedName.trimmingCharacters(in: .whitespacesAndNewlines),
                                 editedDescription, selectedCategory)
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
            Button("Enable All") { features = TubeCleanerDeArrowPreference.Features() }
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
struct CodeEditorSheet: View {
    @ObservedObject var editorController: CodeMirrorEditorController
    let onTextChanged: (String) -> Void
    let onPaste: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLineWrappingEnabled = false
    @State private var originalText: String?
    @State private var didFinish = false

    var body: some View {
        Group {
            #if os(iOS)
            CompatibleNavigationStack {
                if #available(iOS 16.0, *) {
                    editorBody
                        .background(Color(.systemGray6))
                        .navigationTitle("Editor")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(.hidden, for: .navigationBar)
                } else {
                    editorBody
                        .background(Color(.systemGray6))
                        .navigationTitle("Editor")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            #else
            editorBody
                .frame(width: 1000, height: 700)
            #endif
        }
        .task { originalText = await editorController.currentText() }
        .interactiveDismissDisabled()
        .onDisappear {
            if !didFinish, let originalText { editorController.replaceText(originalText, markClean: true) }
        }
    }

    private var editorBody: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Done", action: finish).keyboardShortcut(.defaultAction)
                }
                HStack(spacing: 10) {
                    Spacer()
                    SourceViewerControls(wrapsLines: $isLineWrappingEnabled) { editorController.openSearch() }
                    Button(action: editorController.undo) { Label("Undo", systemImage: "arrow.uturn.backward") }
                    Button(action: editorController.redo) { Label("Redo", systemImage: "arrow.uturn.forward") }
                    Button(action: onPaste) { Label("Paste", systemImage: "doc.on.clipboard") }
                }
                .labelStyle(.iconOnly)
            }
            .disabled(originalText == nil)
            .padding(12)
            #if os(macOS)
            .liquidGlassCompat(cornerRadius: 12, material: .regularMaterial)
            #endif
            .padding(12)

            CodeMirrorTextEditor(
                controller: editorController,
                isEditable: true,
                isLineWrappingEnabled: isLineWrappingEnabled
            )
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 360)
            #else
            .frame(minHeight: 260)
            #endif
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func finish() {
        Task { @MainActor in
            didFinish = true
            onTextChanged(await editorController.currentText())
            dismiss()
        }
    }
}

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

    init(userScriptManager: UserScriptManager, onScriptAdded: @escaping () -> Void) {
        self.userScriptManager = userScriptManager
        self.onScriptAdded = onScriptAdded
        _editorController = StateObject(wrappedValue: CodeMirrorEditorController(text: ""))
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
        Group {
            #if os(iOS)
            iosBody
            #elseif os(macOS)
            macosBody
            #endif
        }
        .interactiveDismissDisabled(isAdding)
        #if os(macOS)
        .onAppear {
            urlFieldFocused = addMode == .url
        }
        .onChangeCompat(of: addMode) { _, newValue in
            urlFieldFocused = newValue == .url
            if newValue == .text {
                scheduleEditorMetadataRefresh()
            }
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
            isReviewingURLs = false
            if mode == .single { urlInput = FilterListURLSupport.normalizeSingleURLInput(urlInput) }
            validateInput(urlInput)
            fetchURLMetadata()
        }
        .onChangeCompat(of: addMode) { _, mode in
            if mode == .url { fetchURLMetadata() } else {
                urlMetadataTask?.cancel()
                urlMetadataGeneration += 1
                isFetchingURLMetadata = false
            }
        }
        .onChangeCompat(of: textInput) { _, _ in
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
            CodeEditorSheet(
                editorController: editorController,
                onTextChanged: applyEditorText,
                onPaste: pasteScriptFromClipboard
            )
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: allowedImportTypes) { result in
            switch result {
            case .success(let url):
                stageFile(at: url)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    fileImportError = error.localizedDescription
                }
            }
        }
    }

    #if os(iOS)
    private var iosBody: some View {
        AddContentIOSSheet(
            title: "Add Userscript or Userstyle",
            isLoading: isAdding,
            buttonTitle: { LocalizedStringKey(addURLButtonTitle) },
            isSubmitDisabled: !canSubmit || isAdding,
            onDismiss: { dismiss() },
            onSubmit: submit
        ) {
            addTabs
        }
    }
    #endif

    private var addTabs: some View {
        TabView(selection: $addMode) {
            urlTab
                .tag(AddMode.url)
                .tabItem { Label("URL", systemImage: "link") }

            textTab
                .tag(AddMode.text)
                .tabItem { Label("Text", systemImage: "text.alignleft") }

            fileTab
                .tag(AddMode.file)
                .tabItem { Label("File", systemImage: "doc") }
        }
    }

    private var urlTab: some View {
        AddContentPanelLayout {
            AddContentCard {
                urlFormFields
                validationMessage
            }
            requirementsPanel
        }
    }

    private var textTab: some View {
        AddContentPanelLayout {
            AddContentCard { userScriptMetaFields }
            simpleTextContent
            editorRequirementsPanel
        }
        .task {
            scheduleEditorMetadataRefresh()
        }
    }

    private var fileTab: some View {
        AddContentPanelLayout {
            AddContentCard {
                fileSelectionButton
                if stagedFile != nil {
                    userScriptMetaFields
                }
                fileImportMessage
            }
            fileRequirementsPanel
        }
    }

    private var fileSelectionButton: some View {
        AddContentFileSelectionButton(
            filename: stagedFile?.filename,
            isLoading: isStagingFile,
            isDisabled: isAdding
        ) {
            showingFileImporter = true
            fileImportError = nil
        }
    }

    private var simpleTextContent: some View {
        AddContentSourceCard(title: "Script Content", isDisabled: isAdding,
            onPaste: pasteScriptFromClipboard, onOpenEditor: openEditorSheet) {
                if #available(iOS 16.0, macOS 13.0, *) {
                    scriptTextEditor.scrollContentBackground(.hidden)
                } else {
                    scriptTextEditor
                }
            }
    }

    private var scriptTextEditor: some View {
        TextEditor(text: $textInput)
            .font(.system(.body, design: .monospaced))
            .autocorrectionDisabled()
            .focused($textInputFocused)
            .frame(minHeight: 260, idealHeight: 320, maxHeight: 500)
            .accessibilityLabel(Text("Script Content"))
    }

    #if os(macOS)
    private var macosBody: some View {
        AddContentMacSheet(
            title: "Add Userscript or Userstyle",
            isLoading: isAdding,
            minHeight: 500,
            onDismiss: { dismiss() },
            isDismissDisabled: isAdding
        ) {
            modePickerCard
            macosModeContent
        } action: {
            addButton
        }
    }

    private var modePickerCard: some View {
        AddContentModePicker(selection: $addMode)
    }

    @ViewBuilder
    private var macosModeContent: some View {
        switch addMode {
        case .url:
            VStack(alignment: .leading, spacing: 16) {
                macosURLCard
                requirementsPanel
            }
        case .text:
            VStack(alignment: .leading, spacing: 16) {
                macosTextCard
                editorRequirementsPanel
            }
        case .file:
            VStack(alignment: .leading, spacing: 16) {
                macosFileCard
                fileRequirementsPanel
            }
        }
    }

    private var macosURLCard: some View {
        AddContentCard {
            urlFormFields

            HStack {
                Spacer()
                validationBadge
            }
            validationMessage
        }
    }

    private var macosTextCard: some View {
        VStack(spacing: 16) {
            AddContentCard { userScriptMetaFields }
            simpleTextContent
        }
    }

    private var macosFileCard: some View {
        AddContentCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Import File")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Local imports won't auto-update; re-import to replace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            fileSelectionButton
            if stagedFile != nil {
                userScriptMetaFields
            }
            if let fileImportError {
                Text(fileImportError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    #endif

    private var metadataRequirementText: LocalizedStringKey {
        "Include the // ==UserScript== metadata block (or /* ==UserStyle== */ for userstyles) so wBlock can read the name and URL patterns."
    }

    private var requirementsPanel: some View {
        AddContentRequirementsPanel(requirements: [
            AddContentRequirement(systemImage: "link", text: "Starts with http:// or https://"),
            AddContentRequirement(systemImage: "doc.text", text: "Ends with .js, .user.js, .user.css, .less, .sass, .scss, .styl, or .pcss"),
            AddContentRequirement(systemImage: "globe", text: "Include a host name"),
            AddContentRequirement(systemImage: "doc.badge.gearshape", text: metadataRequirementText)
        ])
    }

    private var editorRequirementsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            AddContentRequirementsPanel(requirements: AddContentRequirement.localImport(fromFile: false) + [
                AddContentRequirement(systemImage: "doc.badge.gearshape", text: metadataRequirementText)
            ])
            if let editorImportError {
                Text(editorImportError)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var userScriptMetaFields: some View {
        AddContentMetadataFields(name: $stagedName, description: $stagedDescription,
                                 category: $selectedCategory, categories: FilterListCategory.userScriptCategories,
                                  categoryName: { $0.userScriptCategoryName })
    }

    private var fileImportMessage: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Local imports won't auto-update; re-import to replace.")
                .foregroundStyle(.secondary)
            if let fileImportError {
                Text(fileImportError)
                    .foregroundStyle(.orange)
            }
        }
        .font(.footnote)
    }

    private var fileRequirementsPanel: some View {
        AddContentRequirementsPanel(requirements: AddContentRequirement.localImport(fromFile: true) + [
            AddContentRequirement(systemImage: "doc.badge.gearshape", text: metadataRequirementText)
        ])
    }

    private var addURLButtonTitle: String {
        if addMode == .url && urlEntryMode == .bulk {
            return isReviewingURLs ? "Add URLs" : "Next"
        }
        return "Add"
    }

    private var urlFormFields: some View {
        Group {
            if urlEntryMode == .bulk && isReviewingURLs {
                Button("Back") { isReviewingURLs = false; urlMetadataTask?.cancel(); isFetchingURLMetadata = false }
            } else {
                Picker("URL entry mode", selection: $urlEntryMode) {
                    Text("Single URL").tag(URLEntryMode.single)
                    Text("Bulk URLs").tag(URLEntryMode.bulk)
                }
                .pickerStyle(.segmented)
                .disabled(isAdding)
                urlInputEditor
            }
            if urlEntryMode == .single || isReviewingURLs {
                if isFetchingURLMetadata { ProgressView().controlSize(.small) }
                ForEach(parsedURLs, id: \.absoluteString) { url in
                    VStack(alignment: .leading, spacing: 6) {
                        if urlEntryMode == .bulk {
                            Text(url.absoluteString).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        AddContentMetadataFields(
                            name: Binding(get: { urlNames[url.absoluteString] ?? urlMetadata[url.absoluteString]?.title ?? "" }, set: { urlNames[url.absoluteString] = $0 }),
                            description: Binding(get: { urlDescriptions[url.absoluteString] ?? urlMetadata[url.absoluteString]?.description ?? "" }, set: { urlDescriptions[url.absoluteString] = $0 }),
                            category: Binding(get: { urlCategories[url.absoluteString] ?? selectedCategory }, set: { urlCategories[url.absoluteString] = $0 }),
                            categories: FilterListCategory.userScriptCategories,
                            categoryName: { $0.userScriptCategoryName }
                        )
                    }
                }
            }
        }
    }

    private func fetchURLMetadata() {
        urlMetadataTask?.cancel()
        urlMetadataGeneration += 1
        let generation = urlMetadataGeneration
        guard urlEntryMode == .single || isReviewingURLs else { isFetchingURLMetadata = false; return }
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

    private var urlInputEditor: some View {
        AddContentField(title: urlEntryMode == .single ? "URL" : "URLs") {
            AddContentURLInput(
                text: $urlInput,
                isFocused: $urlFieldFocused,
                isBulk: urlEntryMode == .bulk,
                singlePlaceholder: { Text(verbatim: "https://example.com/script.user.js") },
                bulkPlaceholder: { Text(verbatim: "https://example.com/script.user.js") },
                accessibilityLabel: urlEntryMode == .single ? "URL" : "URLs",
                isDisabled: isAdding,
                onPaste: pasteFromClipboard,
                pasteTitle: urlEntryMode == .single ? "Paste URL" : "Paste URLs",
                pasteButtonUsesRow: true
            )
        }
    }


    private var urlValidationFeedback: ValidationState {
        if let urlImportError { return .invalid(urlImportError) }
        return validationState
    }

    private var validationBadge: some View {
        Group {
            switch urlValidationFeedback {
            case .idle:
                EmptyView()
            case .invalid:
                Label("Invalid", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .valid:
                Label("Ready", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: validationState)
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


    private var addButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isAdding {
                    ProgressView()
                        .scaleEffect(0.9)
                }
                Text(LocalizedStringKey(isAdding ? "Adding…" : addURLButtonTitle))
                    .fontWeight(.semibold)
            }
        }
        .primaryActionButtonStyle()
        .disabled(!canSubmit || isAdding)
        .keyboardShortcut(.defaultAction)
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
            if urlEntryMode == .bulk && !isReviewingURLs {
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
                    if let error = await userScriptManager.addUserScript(from: url, nameOverride: urlNames[url.absoluteString], descriptionOverride: urlDescriptions[url.absoluteString], category: urlCategories[url.absoluteString] ?? selectedCategory) {
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
        editorController.replaceText(textInput, markClean: true)
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
