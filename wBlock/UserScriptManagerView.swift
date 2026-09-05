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
        [.scripts, .custom]
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
    let lastUpdatedFormatted: String?
    let isLocal: Bool
    let isDownloaded: Bool
    let updatesAutomatically: Bool
    let isUserStyle: Bool
    let category: FilterListCategory
    let displayCategory: UserScriptDisplayCategory
    let isBuiltIn: Bool
    let isIntegrated: Bool
    let isCustom: Bool
    let isBeta: Bool
    let isDarkReader: Bool
    let isTubeCleaner: Bool

    init(
        script: UserScript,
        isDownloaded: Bool,
        isBuiltIn: Bool,
        builtInDisplayRole: BuiltInUserScriptDisplayRole?,
        isBeta: Bool = false,
        isDarkReader: Bool = false,
        isTubeCleaner: Bool = false
    ) {
        id = script.id
        name = script.name
        localizedDisplayName = script.localizedDisplayName
        localizedDisplayDescription = script.localizedDisplayDescription
        url = script.url
        updateURL = script.updateURL
        isEnabled = script.isEnabled
        version = script.version
        lastUpdatedFormatted = script.lastUpdatedFormatted
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
    }
}

private typealias UserScriptSectionKind = UserScriptDisplayCategory

private struct UserScriptDisplaySection: Identifiable {
    let id: UserScriptSectionKind
    let title: LocalizedStringKey
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
            lastAutofilledName = name.isEmpty ? "Pasted Userscript" : name
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
    let tabSelection: Int
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
    @State private var showingAddScriptSheet = false
    @State private var selectedScript: SelectedUserScript?
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
                Text("Apply")
                    .fontWeight(.semibold)
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
        let filteredByEnabled = showOnlyEnabled ? scripts.filter(\.isEnabled) : scripts
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

        return filteredBySearch.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var displayedScriptSections: [UserScriptDisplaySection] {
        UserScriptDisplayCategorySupport.orderedGroups(
            displayedScripts,
            category: { $0.displayCategory }
        ).map { group in
            UserScriptDisplaySection(
                id: group.category,
                title: LocalizedStringKey(group.category.rawValue),
                scripts: group.items
            )
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
        .sheet(item: $selectedScript, onDismiss: {
            refreshScripts()
        }) { selection in
            if selection.action == .info {
                UserScriptInfoView(
                    scriptId: selection.id,
                    userScriptManager: userScriptManager
                )
                .tallInfoSheetPresentationCompat()
            } else {
                UserScriptContentView(
                    scriptId: selection.id,
                    userScriptManager: userScriptManager,
                    startsEditing: selection.action == .editContent
                )
            }
        }
        .sheet(item: $selectedCategoryInfo) { category in
            UserScriptCategoryInfoView(
                category: category,
                defaultScriptNames: defaultScriptNames(for: category),
                onReset: { resetCategory(category) }
            )
            .infoSheetPresentationCompat()
        }
        .onAppear {
            refreshScripts()
            showOnlyEnabled = ProtobufDataManager.shared.getUserScriptShowEnabledOnly()
        }
        .onReceive(userScriptManager.$userScripts) { updatedScripts in
            // @Published emits in willSet, so use the emitted array instead of
            // reading the manager's still-stale value during this callback.
            refreshScripts(updatedScripts)
        }
        .onChangeCompat(of: tabSelection) { _, _ in
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
                    Section {
                        ForEach(scriptSection.scripts) { script in
                            scriptRowView(script: script)
                        }
                    } header: {
                        displaySectionHeader(scriptSection)
                    }
                }
            }        }
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
                        Image(systemName: "magnifyingglass")
                    }
                }
                Button {
                    showingAddScriptSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    showOnlyEnabled.toggle()
                    ProtobufDataManager.shared.setUserScriptShowEnabledOnly(showOnlyEnabled)
                } label: {
                    Image(
                        systemName: showOnlyEnabled
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
        ScrollView {
            VStack(spacing: 20) {
                statsCardsView

                if scripts.isEmpty {
                    emptyStateView
                        .padding(.top, 40)
                } else if sections.isEmpty {
                    noSearchResultsView
                        .padding(.top, 40)
                } else {
                    scriptsListView(sections: sections)
                }

                Spacer(minLength: 20)
            }
            .padding(.vertical)
        }
        .keyboardScrollable()
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
    private var macScriptsToolbar: some ViewModifier {
        MacActionsToolbar(isSearchExpanded: showSearch) {
            Button {
                showingAddScriptSheet = true
            } label: {
                Label("Add Userscript or Userstyle", systemImage: "plus")
            }
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
                isTubeCleaner: userScriptManager.isTubeCleaner(script)
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
        .padding(.horizontal)
    }

    private func displaySectionHeader(_ section: UserScriptDisplaySection) -> some View {
        HStack(spacing: 6) {
            Text(section.title)
                .foregroundStyle(.primary)
                .textCase(.none)
            Button {
                selectedCategoryInfo = section.id
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .noFocusRingCompat()
            .foregroundStyle(.secondary)
            .accessibilityLabel("Info")
        }
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

    #if os(macOS)
    private func scriptsListView(sections: [UserScriptDisplaySection]) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(sections) { scriptSection in
                macOSUserScriptSectionView(section: scriptSection)
            }
        }        .padding(.horizontal)
    }

    private func macOSUserScriptSectionView(
        section: UserScriptDisplaySection
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(section.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Button {
                            selectedCategoryInfo = section.id
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.plain)
                        .noFocusRingCompat()
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Info")
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(section.scripts.indices, id: \.self) { index in
                    scriptRowView(script: section.scripts[index])

                    if index < section.scripts.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    #endif

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
            // The info tap lives on the text column only. A row-wide tap gesture
            // competes with the switch on iOS 17, where the gesture wins and a tap
            // on the switch opens the info sheet instead of toggling the script.
            HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(script.localizedDisplayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !script.localizedDisplayDescription.isEmpty {
                    Text(script.localizedDisplayDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text(script.isIntegrated ? "Integrated" : (script.isUserStyle ? "Userstyle" : "Userscript"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if script.isLocal {
                        Badge(text: "Local Import", color: .blue)
                    } else if script.isCustom {
                        Badge(text: "Custom", color: .blue)
                    }
                    if script.isBeta {
                        Badge(text: "Beta", color: .orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    if !script.version.isEmpty {
                        Text(
                            LocalizedStrings.format(
                                "Version %@",
                                comment: "Userscript version label",
                                script.version
                            )
                        )
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                    if let lastUpdated = script.lastUpdatedFormatted {
                        if !script.version.isEmpty {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                        Text(lastUpdated)
                            .font(.caption2)
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
                    TubeCleanerFeaturesPicker(
                        features: Binding(
                            get: { userScriptManager.tubeCleanerFeatures },
                            set: { userScriptManager.setTubeCleanerFeatures($0) }
                        )
                    )
                    TubeCleanerDeArrowPicker(
                        settings: Binding(
                            get: { userScriptManager.tubeCleanerDeArrow },
                            set: { userScriptManager.setTubeCleanerDeArrow($0) }
                        )
                    )
                }
            }

            Spacer(minLength: 0)
            }
            .contentShape(.interaction, Rectangle())
            .onTapGesture {
                // Defer to avoid race with context menu dismissal on iOS
                DispatchQueue.main.async {
                    selectedScript = SelectedUserScript(id: script.id, action: .info)
                }
            }

            HStack(spacing: 8) {
                if !script.isLocal || script.isDownloaded {
                    ContentDownloadControl(
                        isDownloaded: script.isDownloaded,
                        isDownloading: downloadingScriptIDs.contains(script.id),
                        name: script.name, action: { downloadScript(script) }
                    )
                }
                Toggle("", isOn: Binding(
                    get: { displayedEnabled || downloadingScriptIDs.contains(script.id) },
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
                .disabled(
                    isToggleInFlight
                        || downloadingScriptIDs.contains(script.id)
                        || (script.isLocal && !script.isDownloaded)
                )
                .frame(alignment: .center)
            }
        }
        .id(script.id)
        .contextMenu {
            let actions = ContextMenuActionAvailability.userScriptActions(
                isBuiltIn: script.isBuiltIn,
                isLocal: script.isLocal,
                isDownloaded: script.isDownloaded
            )
            if actions.contains(.info) {
                Button {
                    selectedScript = SelectedUserScript(id: script.id, action: .info)
                } label: {
                    Label("Info", systemImage: "info.circle")
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
            if actions.contains(.download) {
                Button {
                    downloadScript(script)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .disabled(downloadingScriptIDs.contains(script.id))
            }
            if actions.contains(.deleteScript),
               let managedScript = userScriptManager.userScript(withId: script.id) {
                Button(role: .destructive) {
                    Task {
                        await ConcurrentLogManager.shared.info(.userScript, LocalizedStrings.text("Removing userscript"), metadata: ["script": script.name])
                        await userScriptManager.removeUserScript(managedScript)
                        refreshScripts()
                    }
                } label: {
                    Label(
                        script.isUserStyle ? "Delete Style" : "Delete Script",
                        systemImage: "trash"
                    )
                }
            }
        }
        #if os(macOS)
        .padding(16)
        #endif
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(script.localizedDisplayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                if isBeta {
                    Text("Beta")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .cornerRadius(4)
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
    let isIntegrated: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(InfoBadgeSupport.userScriptBadges(
                    script,
                    isDownloaded: isDownloaded,
                    isBuiltIn: isBuiltIn,
                    isIntegrated: isIntegrated
                ).enumerated()), id: \.offset) { _, badge in
                    InfoBadgeView(kind: badge)
                }
            }
        }
    }
}

private struct ScriptFileInfoView: View {
    let contentLength: Int
    let formatFileSize: (Int) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File Information").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
            HStack {
                Text("Size:").font(.caption2).foregroundStyle(.secondary)
                Text(formatFileSize(contentLength)).font(.caption).fontWeight(.medium).foregroundStyle(.primary)
                Spacer()
            }.padding(.horizontal, 8).padding(.vertical, 6).cornerRadius(6)
        }
    }
}

private struct ScriptURLView: View {
    let script: UserScript

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source URL").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
            if let url = script.url {
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = url.absoluteString
                    #elseif os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    #endif
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
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


private struct ScriptUpdateSettingsView: View {
    let updatesAutomatically: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Automatic Updates", isOn: Binding(
                get: { updatesAutomatically },
                set: onChange
            ))
            .toggleStyle(.switch)

            Text("Turn this off to keep the current version when wBlock updates scripts in bulk or on a schedule.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(updatesAutomatically ? 0 : 0.08))
        .cornerRadius(8)
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
    let onUpdatesAutomaticallyChanged: (Bool) -> Void
    var fillsAvailableSpace = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScriptNameAndDescriptionView(script: script, isBeta: isBeta)
            ScriptStatusBadgesView(
                script: script,
                isDownloaded: contentLength > 0,
                isBuiltIn: isBuiltIn,
                isIntegrated: isIntegratedUserScript(
                    script,
                    isBuiltIn: isBuiltIn,
                    builtInDisplayRole: builtInDisplayRole
                )
            )
            if script.url != nil || script.updateURL != nil || script.downloadURL != nil {
                ScriptUpdateSettingsView(
                    updatesAutomatically: script.updatesAutomatically,
                    onChange: onUpdatesAutomaticallyChanged
                )
            }
            if contentLength > 0 {
                ScriptFileInfoView(contentLength: contentLength, formatFileSize: formatFileSize)
            }
            if script.url != nil { ScriptURLView(script: script) }
            if !script.matches.isEmpty { ScriptMatchPatternsView(script: script, isPatternsExpanded: $isPatternsExpanded) }
            if fillsAvailableSpace {
                Spacer()
            }
        }
    }
}

struct UserScriptInfoView: View {
    let scriptId: UUID
    var userScriptManager: UserScriptManager

    @Environment(\.dismiss) private var dismiss
    @State private var script: UserScript?
    @State private var isPatternsExpanded = false
    @State private var isLoading = true

    var body: some View {
        Group {
            if let script {
                #if os(iOS)
                NavigationView {
                    ScrollView {
                        UserScriptInfoSidebar(
                            script: script,
                            contentLength: script.content.count,
                            isPatternsExpanded: $isPatternsExpanded,
                            formatFileSize: formatFileSize,
                            isBuiltIn: userScriptManager.isDefaultUserScript(script),
                            builtInDisplayRole: userScriptManager.builtInDisplayRole(for: script),
                            isBeta: userScriptManager.isBeta(for: script),
                            onUpdatesAutomaticallyChanged: setUpdatesAutomatically
                        )
                        .padding()
                    }
                    // The sidebar already shows the name as its heading; a nav
                    // title on top of it read as a duplicate (#628).
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            SheetDoneButton(action: { dismiss() }, usesAutomaticStyle: true)
                        }
                    }
                }
                #else
                UserScriptInfoSidebar(
                    script: script,
                    contentLength: script.content.count,
                    isPatternsExpanded: $isPatternsExpanded,
                    formatFileSize: formatFileSize,
                    isBuiltIn: userScriptManager.isDefaultUserScript(script),
                    builtInDisplayRole: userScriptManager.builtInDisplayRole(for: script),
                    isBeta: userScriptManager.isBeta(for: script),
                    onUpdatesAutomaticallyChanged: setUpdatesAutomatically,
                    fillsAvailableSpace: false
                )
                .padding(20)
                .frame(width: 460)
                .safeAreaInset(edge: .top, alignment: .trailing, spacing: 0) {
                    SheetDoneButton { dismiss() }
                        .padding(.top, 16)
                        .padding(.trailing, 20)
                }
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
        .task(id: scriptId) {
            isLoading = true
            script = await userScriptManager.userScriptEditorSnapshot(withId: scriptId)
            isLoading = false
        }
    }

    private func setUpdatesAutomatically(_ updatesAutomatically: Bool) {
        guard var currentScript = script else { return }
        currentScript.updatesAutomatically = updatesAutomatically
        script = currentScript
        Task {
            await userScriptManager.setUserScript(currentScript, updatesAutomatically: updatesAutomatically)
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// View Content and Edit Content both open the CodeMirror source sheet directly,
/// matching the filter list viewer (#616). Metadata lives in UserScriptInfoView.
struct UserScriptContentView: View {
    let scriptId: UUID
    var userScriptManager: UserScriptManager
    var startsEditing: Bool = false
    @State private var script: UserScript?
    @State private var loadedContent = ""
    @State private var isLoadingContent = true

    var body: some View {
        Group {
            if let script {
                UserScriptSourceSheet(
                    script: script,
                    initialContent: loadedContent,
                    canEdit: script.isLocal && !userScriptManager.isDefaultUserScript(script),
                    startsEditing: startsEditing,
                    onSave: { newContent, name, description in
                        if let error = await userScriptManager.saveEditedContent(for: script.id, newContent: newContent) {
                            return error
                        }
                        await userScriptManager.setUserScriptMetadataOverrides(
                            for: script.id,
                            name: name,
                            description: description
                        )
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
    let onSave: (String, String, String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var editorController: CodeMirrorEditorController
    @State private var isEditing: Bool
    @State private var isLineWrappingEnabled = false
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var editedName: String
    @State private var editedDescription: String

    init(
        script: UserScript,
        initialContent: String,
        canEdit: Bool,
        startsEditing: Bool = false,
        onSave: @escaping (String, String, String) async -> String?
    ) {
        self.script = script
        self.initialContent = initialContent
        self.canEdit = canEdit
        self.onSave = onSave
        _editorController = StateObject(wrappedValue: CodeMirrorEditorController(text: initialContent, isUserStyle: script.isUserStyle))
        _isEditing = State(initialValue: startsEditing && canEdit)
        _editedName = State(initialValue: script.name)
        _editedDescription = State(initialValue: script.description)
    }

    var body: some View {
        #if os(iOS)
        CompatibleNavigationStack {
            sourceSheetBody
                .background(Color(.systemGray6))
                .navigationTitle("Script Content")
                .navigationBarTitleDisplayMode(.inline)
        }
        #else
        sourceSheetBody
            .frame(width: 1000, height: 700)
        #endif
    }

    private var sourceSheetBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                #if os(macOS)
                VStack(alignment: .leading, spacing: 2) {
                    Text(script.localizedDisplayName)
                        .font(.headline)
                    (script.isUserStyle ? Text("Style Content") : Text("Script Content"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif

                SourceViewerControls(wrapsLines: $isLineWrappingEnabled) {
                    editorController.openSearch()
                }

                Spacer()

                if isEditing {
                    Button("Cancel") {
                        handleCancel()
                    }

                    Button {
                        Task {
                            await saveChanges()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 12, height: 12)
                            }
                            Text("Save")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || (!editorController.isDirty && !hasMetadataChanges))
                } else {
                    if canEdit {
                        Button("Edit") {
                            isEditing = true
                            DispatchQueue.main.async {
                                editorController.focus()
                            }
                        }
                    }

                    SheetDoneButton {
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            if let analysis = editorController.analysis, analysis.isLargeDocument {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(LocalizedStrings.text(
                        "Highlighting disabled for performance",
                        comment: "CodeMirror source sheet: large document note"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                Divider()
            }

            if isEditing && canEdit {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Description", text: $editedDescription)
                        .textFieldStyle(.roundedBorder)
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }

            CodeMirrorTextEditor(
                controller: editorController,
                isEditable: isEditing && canEdit,
                isLineWrappingEnabled: isLineWrappingEnabled
            )
        }
    }

    private var hasMetadataChanges: Bool {
        editedName.trimmingCharacters(in: .whitespacesAndNewlines) != script.name
            || editedDescription.trimmingCharacters(in: .whitespacesAndNewlines) != script.description
    }

    @MainActor
    private func saveChanges() async {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = LocalizedStrings.text(
                "Title is required.",
                comment: "Userscript metadata validation error"
            )
            return
        }

        isSaving = true
        let newContent = await editorController.currentText()
        let error = await onSave(newContent, trimmedName, editedDescription)
        isSaving = false
        if let error {
            validationMessage = error
        } else {
            dismiss()
        }
    }

    private func handleCancel() {
        editorController.discardChanges()
        isEditing = false
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

/// DeArrow settings for the built-in Tube Cleaner, shown as a compact menu on
/// its list row (#611). The pill reads On/Off; the menu holds the toggles the
/// script's own "DA" panel used to offer.
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

private struct TubeCleanerDeArrowPicker: View {
    @Binding var settings: TubeCleanerDeArrowPreference.Settings

    var body: some View {
        Menu {
            Toggle("Enable DeArrow", isOn: $settings.enabled)
            Divider()
            Toggle("Replace Titles", isOn: $settings.replaceTitles)
                .disabled(!settings.enabled)
            Toggle("Replace Thumbnails", isOn: $settings.replaceThumbnails)
                .disabled(!settings.enabled)
            Toggle("Random Frame When No Thumbnail", isOn: $settings.randomThumbnails)
                .disabled(!settings.enabled || !settings.replaceThumbnails)
            Toggle("Show Original on Hover", isOn: $settings.showOriginalOnHover)
                .disabled(!settings.enabled)
            Divider()
            // DeArrow data is CC BY-NC-SA 4.0; the credit link is a license term.
            Link("Using DeArrow", destination: URL(string: "https://dearrow.ajay.app/")!)
            Link("Donate to DeArrow", destination: URL(string: "https://dearrow.ajay.app/donate/")!)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: settings.enabled ? "arrow.uturn.down.circle.fill" : "arrow.uturn.down.circle")
                    .imageScale(.small)
                Text(settings.enabled ? "DeArrow: On" : "DeArrow: Off")
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
        .accessibilityLabel(settings.enabled ? "DeArrow: On" : "DeArrow: Off")
        .padding(.top, 2)
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
        .onDisappear {
            Task { @MainActor in
                onTextChanged(await editorController.currentText())
            }
        }
    }

    private var editorBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    editorController.openSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .accessibilityLabel("Search")

                Button {
                    isLineWrappingEnabled.toggle()
                } label: {
                    Label("Wrap Lines", systemImage: isLineWrappingEnabled ? "text.justify.left" : "text.alignleft")
                }
                .foregroundStyle(isLineWrappingEnabled ? Color.accentColor : Color.secondary)
                .accessibilityValue(
                    isLineWrappingEnabled
                        ? String(localized: "On")
                        : String(localized: "Off")
                )

                Spacer()

                Button(action: onPaste) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }

                SheetDoneButton(action: finish)
            }
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
            .frame(minWidth: 420, minHeight: 360)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func finish() {
        Task { @MainActor in
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
    @State private var selectedCategory: FilterListCategory = .scripts
    @State private var editorMetadataState = EditorMetadataAutofillState()
    @State private var editorMetadataRefreshTask: Task<Void, Never>?
    @State private var metadataRefreshGeneration = 0
    @State private var addMode: AddMode = .url
    @State private var showHints: Bool = false
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
            validateInput(newValue)
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
        CompatibleNavigationStack {
            addTabs
                .navigationTitle("Add Userscript or Userstyle")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isAdding)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: submit) {
                            if isAdding {
                                ProgressView()
                            } else {
                                Text("Add")
                            }
                        }
                        .disabled(!canSubmit || isAdding)
                    }
                }
        }
        .largeSheetPresentationCompat()
    }

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
        Form {
            Section {
                urlInputEditor

                if parsedURLs.count > 1 {
                    Text("Titles will be created from each URL.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    userScriptMetaFields
                }
                if parsedURLs.count > 1 {
                    AddContentField(title: "Category") { userScriptCategoryPicker.labelsHidden() }
                }
            } footer: {
                validationMessage
            }

            Section {
                requirementsPanel
            }
        }
    }

    private var textTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AddContentCard { simpleTextContent }
                editorRequirementsPanel
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .task {
            scheduleEditorMetadataRefresh()
        }
    }

    private var fileTab: some View {
        Form {
            Section {
                fileSelectionButton
                if stagedFile != nil {
                    userScriptMetaFields
                }
            } footer: {
                fileImportMessage
            }

            Section {
                fileRequirementsPanel
            }
        }
    }

    private var fileSelectionButton: some View {
        Button {
            showingFileImporter = true
            fileImportError = nil
        } label: {
            HStack {
                Image(systemName: "doc")
                Text(stagedFile?.filename ?? "Choose File")
                if isStagingFile { ProgressView().controlSize(.small) }
                Spacer()
                if stagedFile != nil {
                    Text("Change File").foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isAdding)
    }
    #endif

    private var simpleTextContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            userScriptMetaFields

            TextEditor(text: $textInput)
                .font(.body)
                .autocorrectionDisabled()
                .focused($textInputFocused)
                .frame(minHeight: 260, idealHeight: 320, maxHeight: 500)
                .padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .accessibilityLabel(Text("Script Content"))

            HStack(spacing: 10) {
                Button(action: pasteScriptFromClipboard) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .disabled(isAdding)

                Button(action: openEditorSheet) {
                    Label("Use Editor", systemImage: "curlybraces")
                }
                .disabled(isAdding)

                Spacer()
            }
            .buttonStyle(.bordered)

        }
    }

    #if os(macOS)
    private var macosBody: some View {
        SheetContainer {
            SheetHeader(title: "Add Userscript or Userstyle", isLoading: isAdding) {
                dismiss()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modePickerCard
                    macosModeContent
                }
                .padding(.horizontal, SheetDesign.contentHorizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }

            SheetBottomToolbar {
                Spacer()
                addButton
            }
        }
        .frame(minWidth: 560, minHeight: 500)
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
            urlInputEditor

            if parsedURLs.count > 1 {
                Text("Titles will be created from each URL.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                AddContentField(title: "Category") { userScriptCategoryPicker.labelsHidden() }
            } else {
                userScriptMetaFields
            }

            HStack {
                Spacer()
                validationBadge
            }
            validationMessage
        }
    }

    private var macosTextCard: some View {
        AddContentCard { simpleTextContent }
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

    private var fileSelectionButton: some View {
        Button {
            showingFileImporter = true
            fileImportError = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc")
                Text(stagedFile?.filename ?? "Choose File")
                if isStagingFile { ProgressView().controlSize(.small) }
                Spacer()
                if stagedFile != nil {
                    Text("Change File").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .noFocusRingCompat()
        .disabled(isAdding)
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
            AddContentRequirementsPanel(requirements: [
                AddContentRequirement(systemImage: "doc.badge.gearshape", text: metadataRequirementText)
            ])
            if let editorImportError {
                Text(editorImportError)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var userScriptCategoryPicker: some View {
        Picker("Category", selection: $selectedCategory) {
            ForEach(FilterListCategory.userScriptCategories) { category in
                Text(category.localizedName).tag(category)
            }
        }
        .pickerStyle(.menu)
    }

    private var userScriptMetaFields: some View {
        AddContentMetadataFields(name: $stagedName, description: $stagedDescription,
                                 category: $selectedCategory, categories: FilterListCategory.userScriptCategories)
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
        AddContentRequirementsPanel(requirements: [
            AddContentRequirement(systemImage: "doc.badge.gearshape", text: metadataRequirementText)
        ])
    }

    private var urlInputEditor: some View {
        AddContentField(title: "URLs") {

            ZStack(alignment: .topLeading) {
                TextEditor(text: $urlInput)
                    .font(.body)
                    .autocorrectionDisabled()
                    .focused($urlFieldFocused)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif

                if urlInput.isEmpty {
                    Text(verbatim: "https://example.com/script.user.js")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        #if os(macOS)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        #else
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        #endif
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 64, maxHeight: 96)
            .background(.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )
            .accessibilityLabel("URLs")

            HStack {
                compactPasteButton
                Spacer()
            }
        }
    }

    private var compactPasteButton: some View {
        AddContentPasteButton(action: pasteFromClipboard).disabled(isAdding)
    }

    private var validationBadge: some View {
        Group {
            switch validationState {
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
                switch validationState {
                case .idle:
                    Text("wBlock will fetch and enable the script automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .invalid(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                case .valid:
                    Text("Looks good! Tap Add to continue.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if let urlImportError {
                Text(urlImportError)
                    .font(.caption)
                    .foregroundStyle(.orange)
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
                Text(LocalizedStringKey(isAdding ? "Adding…" : "Add"))
                    .fontWeight(.semibold)
            }
        }
        .primaryActionButtonStyle()
        .disabled(!canSubmit || isAdding)
        .keyboardShortcut(.defaultAction)
    }

    private var canSubmit: Bool {
        if isAdding { return false }
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

            isAdding = true
            urlImportError = nil

            Task(priority: .userInitiated) {
                for url in urls {
                    await ConcurrentLogManager.shared.info(.userScript, LocalizedStrings.text("Adding new userscript from URL"), metadata: ["url": url.absoluteString])
                    if let error = await userScriptManager.addUserScript(from: url) {
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        await ConcurrentLogManager.shared.error(.userScript, LocalizedStrings.text("Failed to add userscript from URL"), metadata: ["url": url.absoluteString, "error": message])
                        await MainActor.run {
                            urlImportError = message
                            isAdding = false
                        }
                        return
                    }
                    if let script = userScriptManager.userScripts.first(where: { $0.url == url }) {
                        await userScriptManager.setUserScript(script, category: selectedCategory)
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
                selectedCategory = .scripts
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
            name: UserScriptURLSupport.displayName(forFilename: "Pasted Userscript"),
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
        urlInput = UserScriptURLSupport.appendingPastedURLs(string, to: urlInput)
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
